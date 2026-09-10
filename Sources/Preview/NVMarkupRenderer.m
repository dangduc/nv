#import "NVMarkupRenderer.h"
#import "NVNoteContentSnapshot.h"
#import <poll.h>
#import <fcntl.h>
#import <signal.h>
#import <unistd.h>
#import <errno.h>
#import <libxml/HTMLparser.h>
#import <libxml/HTMLtree.h>

NSString * const NVMarkupRendererErrorDomain = @"NVMarkupRendererErrorDomain";
static const NSUInteger NVSourceByteLimit = 16 * 1024 * 1024;
static const NSUInteger NVOutputByteLimit = 32 * 1024 * 1024;
static const NSUInteger NVDiagnosticByteLimit = 64 * 1024;

static NSError *NVRenderError(NVMarkupRendererErrorCode code, NSString *description) {
    return [NSError errorWithDomain:NVMarkupRendererErrorDomain code:code userInfo:
            [NSDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey]];
}
static NSString *NVEscapedHTML(NSString *string) {
    NSMutableString *escaped = [[string mutableCopy] autorelease];
    for (NSArray *pair in @[@[@"&", @"&amp;"], @[@"<", @"&lt;"], @[@">", @"&gt;"], @[@"\"", @"&quot;"]])
        [escaped replaceOccurrencesOfString:[pair objectAtIndex:0] withString:[pair objectAtIndex:1] options:0 range:NSMakeRange(0, [escaped length])];
    return escaped;
}

typedef struct {
    BOOL limitExceeded;
    BOOL fatalError;
} NVHTMLParseStatus;

static void NVHTMLParseError(void *context, xmlErrorPtr error) {
    htmlParserCtxtPtr parser = context;
    NVHTMLParseStatus *status = parser ? parser->_private : NULL;
    if (!status || !error) return;
    // Libxml 2.9 reports text/depth limits as memory/internal errors. Keep
    // every limit failure: a later recoverable HTML error can replace lastError.
    if (error->code == XML_ERR_NO_MEMORY || error->code == XML_ERR_INTERNAL_ERROR || error->code == XML_ERR_NAME_TOO_LONG)
        status->limitExceeded = YES;
    if (error->level == XML_ERR_FATAL) status->fatalError = YES;
}

// The HTML document is inert even when exported and opened in another browser.
// The WK provider adds a second resource/navigation boundary at load time.
static NSString *NVInertDocument(NSString *input, NSString *title, NSError **error) {
    NSData *UTF8 = [input dataUsingEncoding:NSUTF8StringEncoding];
    htmlParserCtxtPtr parser = htmlNewParserCtxt();
    if (!parser) { if (error) *error = NVRenderError(NVMarkupLimitExceeded, @"The viewer could not allocate its HTML parser."); return nil; }
    NVHTMLParseStatus status = { NO, NO };
    parser->_private = &status;
    parser->sax->serror = NVHTMLParseError;
    // The default HTML SAX handler is version 1. Structured errors require
    // this marker; the existing DOM callbacks and parser userData stay intact.
    parser->sax->initialized = XML_SAX2_MAGIC;
    htmlDocPtr document = htmlCtxtReadMemory(parser, [UTF8 bytes], (int)[UTF8 length], NULL, "UTF-8",
        HTML_PARSE_RECOVER | HTML_PARSE_NONET | HTML_PARSE_NOERROR | HTML_PARSE_NOWARNING);
    htmlFreeParserCtxt(parser);
    if (status.limitExceeded || status.fatalError) {
        if (document) xmlFreeDoc(document);
        if (error) *error = status.limitExceeded ? NVRenderError(NVMarkupLimitExceeded, @"The generated HTML exceeds the parser's resource limits.") : NVRenderError(NVMarkupInvalidOutput, @"The viewer could not read the complete generated HTML.");
        return nil;
    }
    xmlNodePtr root = document ? xmlDocGetRootElement(document) : NULL;
    if (!root) {
        if (document) xmlFreeDoc(document);
        if (error) *error = NVRenderError(NVMarkupInvalidOutput, @"The viewer could not read the generated HTML.");
        return nil;
    }
    NSSet *removed = [NSSet setWithObjects:@"script", @"iframe", @"frame", @"frameset", @"object", @"embed", @"applet", @"base", @"meta", @"portal", @"foreignobject", nil];
    NSSet *controls = [NSSet setWithObjects:@"input", @"textarea", @"select", @"button", @"option", nil];
    NSMutableArray *pending = [NSMutableArray arrayWithObject:[NSValue valueWithPointer:root]];
    NSUInteger nodes = 0;
    while ([pending count]) {
        xmlNodePtr element = [[pending lastObject] pointerValue];
        [pending removeLastObject];
        if (++nodes > 300000) { xmlFreeDoc(document); if (error) *error = NVRenderError(NVMarkupLimitExceeded, @"The rendered document has too many elements."); return nil; }
        NSString *name = [[NSString stringWithUTF8String:(const char *)element->name] lowercaseString];
        if ([removed containsObject:name]) { xmlUnlinkNode(element); xmlFreeNode(element); continue; }
        for (xmlAttrPtr attribute = element->properties; attribute;) {
            xmlAttrPtr next = attribute->next;
            NSString *attributeName = [[NSString stringWithUTF8String:(const char *)attribute->name] lowercaseString];
            if ([attributeName hasPrefix:@"on"] || [@[@"contenteditable", @"autofocus", @"srcdoc", @"action", @"formaction", @"ping", @"download", @"target", @"form", @"http-equiv"] containsObject:attributeName])
                xmlRemoveProp(attribute);
            attribute = next;
        }
        if ([controls containsObject:name]) xmlSetProp(element, BAD_CAST "disabled", BAD_CAST "disabled");
        for (xmlNodePtr child = element->children; child; child = child->next)
            if (child->type == XML_ELEMENT_NODE) [pending addObject:[NSValue valueWithPointer:child]];
    }
    xmlNodePtr body = NULL, head = NULL;
    for (xmlNodePtr child = root->children; child; child = child->next) {
        if (child->type != XML_ELEMENT_NODE) continue;
        if (xmlStrcasecmp(child->name, BAD_CAST "body") == 0) body = child;
        if (xmlStrcasecmp(child->name, BAD_CAST "head") == 0) head = child;
    }
    xmlBufferPtr buffer = xmlBufferCreate();
    if (!buffer) { xmlFreeDoc(document); if (error) *error = NVRenderError(NVMarkupLimitExceeded, @"The viewer could not allocate its document buffer."); return nil; }
    if (body) htmlNodeDump(buffer, document, body);
    else { xmlBufferAdd(buffer, BAD_CAST "<body>", -1); htmlNodeDump(buffer, document, root); xmlBufferAdd(buffer, BAD_CAST "</body>", -1); }
    NSString *content = [[[NSString alloc] initWithBytes:xmlBufferContent(buffer) length:xmlBufferLength(buffer) encoding:NSUTF8StringEncoding] autorelease];
    xmlBufferEmpty(buffer);
    if (head) {
        for (xmlNodePtr child = head->children; child; child = child->next)
            if (child->type == XML_ELEMENT_NODE && (xmlStrcasecmp(child->name, BAD_CAST "style") == 0 || xmlStrcasecmp(child->name, BAD_CAST "link") == 0)) htmlNodeDump(buffer, document, child);
    }
    NSString *style = [[[NSString alloc] initWithBytes:xmlBufferContent(buffer) length:xmlBufferLength(buffer) encoding:NSUTF8StringEncoding] autorelease];
    xmlBufferFree(buffer);
    xmlFreeDoc(document);
    if (!content || !style) { if (error) *error = NVRenderError(NVMarkupInvalidOutput, @"The viewer could not encode the rendered document."); return nil; }
    return [NSString stringWithFormat:@"<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'none'; style-src 'unsafe-inline' nvalt-asset:; img-src data: nvalt-asset:; font-src nvalt-asset:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'\"><title>%@</title><style>:root{color-scheme:light dark}body{font:16px/1.55 -apple-system,BlinkMacSystemFont,sans-serif;margin:24px;overflow-wrap:anywhere}pre,code{font-family:ui-monospace,Menlo,monospace}pre{overflow:auto;padding:12px;background:rgba(128,128,128,.12)}img,video{max-width:100%%}table{border-collapse:collapse}th,td{padding:6px 10px;border:1px solid #888}blockquote{border-left:3px solid #999;padding-left:16px;margin-left:0}input,textarea,select,button{pointer-events:none}a{color:#2679ce}</style>%@</head>%@</html>", NVEscapedHTML(title ?: @""), style, content];
}

@implementation NVMarkupRenderResult
@synthesize snapshot = _snapshot, viewerIdentifier = _viewerIdentifier, HTML = _HTML;
- (id)initWithSnapshot:(NVNoteContentSnapshot *)snapshot viewerIdentifier:(NSString *)identifier HTML:(NSString *)HTML {
    if ((self = [super init])) { _snapshot = [snapshot retain]; _viewerIdentifier = [identifier copy]; _HTML = [HTML copy]; }
    return self;
}
- (void)dealloc { [_snapshot release]; [_viewerIdentifier release]; [_HTML release]; [super dealloc]; }
@end

@interface NVMarkupRenderOperation : NSOperation {
    NVNoteContentSnapshot *_snapshot;
    NSString *_identifier;
    NSBundle *_bundle;
    NSTimeInterval _timeLimit;
    NVMarkupRenderCompletion _completion;
}
- (id)initWithSnapshot:(NVNoteContentSnapshot *)snapshot identifier:(NSString *)identifier bundle:(NSBundle *)bundle timeLimit:(NSTimeInterval)limit completion:(NVMarkupRenderCompletion)completion;
@end

@implementation NVMarkupRenderOperation
- (id)initWithSnapshot:(NVNoteContentSnapshot *)snapshot identifier:(NSString *)identifier bundle:(NSBundle *)bundle timeLimit:(NSTimeInterval)limit completion:(NVMarkupRenderCompletion)completion {
    if ((self = [super init])) { _snapshot = [snapshot retain]; _identifier = [identifier copy]; _bundle = [bundle retain]; _timeLimit = limit; _completion = [completion copy]; }
    return self;
}
- (void)finishWithResult:(NVMarkupRenderResult *)result error:(NSError *)error {
    NVMarkupRenderCompletion callback = nil;
    @synchronized(self) {
        callback = _completion;
        _completion = nil;
    }
    if (!callback) return;
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{ callback(result, error); }];
    [callback release];
}
- (void)cancel {
    [super cancel];
    // NSOperationQueue skips main for queued cancellations. Complete here so
    // every submitted request has one terminal callback, even before it starts.
    [self finishWithResult:nil error:NVRenderError(NVMarkupCancelled, @"Rendering was cancelled.")];
}
- (NSString *)runHelper:(NSString *)path arguments:(NSArray *)arguments input:(NSData *)input error:(NSError **)error {
    NSError *ignoredError = nil;
    if (!error) error = &ignoredError;
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
        *error = NVRenderError(NVMarkupHelperUnavailable, @"The markup converter is unavailable."); return nil;
    }
    NSTask *task = [[[NSTask alloc] init] autorelease];
    NSPipe *inputPipe = [NSPipe pipe], *outputPipe = [NSPipe pipe], *errorPipe = [NSPipe pipe];
    [task setLaunchPath:path]; [task setArguments:arguments];
    [task setStandardInput:inputPipe]; [task setStandardOutput:outputPipe]; [task setStandardError:errorPipe];
    @try { [task launch]; } @catch (NSException *exception) {
        *error = NVRenderError(NVMarkupHelperUnavailable, @"The markup converter could not start."); return nil;
    }
    NSFileHandle *writer = [inputPipe fileHandleForWriting], *reader = [outputPipe fileHandleForReading], *diagnosticReader = [errorPipe fileHandleForReading];
    int inputFD = [writer fileDescriptor], outputFD = [reader fileDescriptor], errorFD = [diagnosticReader fileDescriptor];
    fcntl(inputFD, F_SETFL, fcntl(inputFD, F_GETFL) | O_NONBLOCK);
    fcntl(inputFD, F_SETNOSIGPIPE, 1);
    fcntl(outputFD, F_SETFL, fcntl(outputFD, F_GETFL) | O_NONBLOCK);
    fcntl(errorFD, F_SETFL, fcntl(errorFD, F_GETFL) | O_NONBLOCK);
    NSMutableData *output = [NSMutableData data], *diagnostics = [NSMutableData data];
    NSUInteger offset = 0;
    BOOL inputOpen = YES, outputOpen = YES, errorOpen = YES;
    NSTimeInterval started = [[NSProcessInfo processInfo] systemUptime];
    while (inputOpen || outputOpen || errorOpen || [task isRunning]) {
        if ([self isCancelled]) { *error = NVRenderError(NVMarkupCancelled, @"Rendering was cancelled."); break; }
        if ([[NSProcessInfo processInfo] systemUptime] - started > _timeLimit) { *error = NVRenderError(NVMarkupTimedOut, @"The markup converter exceeded its time limit."); break; }
        struct pollfd descriptors[3] = {{inputOpen ? inputFD : -1, POLLOUT, 0}, {outputOpen ? outputFD : -1, POLLIN, 0}, {errorOpen ? errorFD : -1, POLLIN, 0}};
        poll(descriptors, 3, 20);
        if (inputOpen && (offset == [input length] || descriptors[0].revents)) {
            if (offset < [input length]) {
                ssize_t written = write(inputFD, (const char *)[input bytes] + offset, MIN((NSUInteger)32768, [input length] - offset));
                if (written > 0) offset += written;
                else if (written < 0 && errno != EAGAIN && errno != EINTR) { [writer closeFile]; inputOpen = NO; }
            }
            if (inputOpen && offset == [input length]) { [writer closeFile]; inputOpen = NO; }
        }
        for (NSUInteger index = 1; index < 3; index++) {
            BOOL *open = index == 1 ? &outputOpen : &errorOpen;
            if (!*open || !descriptors[index].revents) continue;
            char buffer[32768];
            ssize_t count = read(descriptors[index].fd, buffer, sizeof(buffer));
            if (count > 0) {
                NSMutableData *destination = index == 1 ? output : diagnostics;
                NSUInteger limit = index == 1 ? NVOutputByteLimit : NVDiagnosticByteLimit;
                [destination appendBytes:buffer length:MIN((NSUInteger)count, limit - [destination length])];
                if (index == 1 && [destination length] == limit) *error = NVRenderError(NVMarkupLimitExceeded, @"The generated HTML exceeds the size limit.");
            } else if (count == 0 || (count < 0 && errno != EAGAIN && errno != EINTR)) {
                [(index == 1 ? reader : diagnosticReader) closeFile]; *open = NO;
            }
        }
        if (*error) break;
    }
    if (*error && [task isRunning]) {
        [task terminate];
        NSTimeInterval deadline = [[NSProcessInfo processInfo] systemUptime] + .2;
        while ([task isRunning] && [[NSProcessInfo processInfo] systemUptime] < deadline) usleep(10000);
        if ([task isRunning]) kill([task processIdentifier], SIGKILL);
    }
    if (inputOpen) [writer closeFile];
    if (outputOpen) [reader closeFile];
    if (errorOpen) [diagnosticReader closeFile];
    if (*error) return nil;
    if ([task terminationStatus] != 0) {
        NSString *detail = [[[NSString alloc] initWithData:diagnostics encoding:NSUTF8StringEncoding] autorelease];
        *error = NVRenderError(NVMarkupHelperFailed, [NSString stringWithFormat:@"The markup converter failed (status %d).%@%@", [task terminationStatus], [detail length] ? @"\n" : @"", detail ?: @""]);
        return nil;
    }
    NSString *converted = [[[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding] autorelease];
    if (!converted) *error = NVRenderError(NVMarkupInvalidOutput, @"The markup converter returned invalid UTF-8.");
    return converted;
}
- (void)main {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSError *error = nil;
    NVMarkupRenderResult *result = nil;
    NSString *source = [_snapshot source];
    NSData *input = [source dataUsingEncoding:NSUTF8StringEncoding];
    NSString *converted = nil;
    if (!source || ![@[@"markdown", @"textile", @"html", @"org"] containsObject:_identifier]) error = NVRenderError(NVMarkupUnsupportedContent, @"This viewer does not support this note's content.");
    else if (!input) error = NVRenderError(NVMarkupInvalidOutput, @"The source cannot be encoded as UTF-8.");
    else if ([input length] > NVSourceByteLimit) error = NVRenderError(NVMarkupLimitExceeded, @"The source exceeds the 16 MB viewer limit.");
    else if ([self isCancelled]) error = NVRenderError(NVMarkupCancelled, @"Rendering was cancelled.");
    else if ([_identifier isEqualToString:@"html"]) converted = source;
    else if ([_identifier isEqualToString:@"markdown"]) converted = [self runHelper:[[_bundle resourcePath] stringByAppendingPathComponent:@"multimarkdown"] arguments:@[] input:input error:&error];
    else if ([_identifier isEqualToString:@"org"]) converted = [self runHelper:[[_bundle resourcePath] stringByAppendingPathComponent:@"nv-org-preview"] arguments:@[] input:input error:&error];
    else converted = [self runHelper:@"/usr/bin/perl" arguments:@[[[_bundle resourcePath] stringByAppendingPathComponent:@"Textile_2.12/textilize.pl"]] input:input error:&error];
    if (converted && !error && ![self isCancelled]) {
        NSString *HTML = NVInertDocument([converted length] ? converted : @"<p></p>", [_snapshot title], &error);
        if (HTML) result = [[[NVMarkupRenderResult alloc] initWithSnapshot:_snapshot viewerIdentifier:_identifier HTML:HTML] autorelease];
    }
    if ([self isCancelled]) { result = nil; error = NVRenderError(NVMarkupCancelled, @"Rendering was cancelled."); }
    [self finishWithResult:result error:error];
    [pool drain];
}
- (void)dealloc { [_snapshot release]; [_identifier release]; [_bundle release]; [_completion release]; [super dealloc]; }
@end

@implementation NVMarkupRenderer
@synthesize timeLimit = _timeLimit;
- (id)init { return [self initWithResourceBundle:[NSBundle mainBundle]]; }
- (id)initWithResourceBundle:(NSBundle *)bundle {
    if ((self = [super init])) { _resourceBundle = [bundle retain]; _queue = [[NSOperationQueue alloc] init]; [_queue setMaxConcurrentOperationCount:2]; [_queue setName:@"nvALT markup rendering"]; _timeLimit = 15.0; }
    return self;
}
- (NSOperation *)renderSnapshot:(NVNoteContentSnapshot *)snapshot viewerIdentifier:(NSString *)identifier completion:(NVMarkupRenderCompletion)completion {
    NVMarkupRenderOperation *operation = [[[NVMarkupRenderOperation alloc] initWithSnapshot:snapshot identifier:identifier bundle:_resourceBundle timeLimit:MAX(.05, MIN(_timeLimit, 60.0)) completion:completion] autorelease];
    [_queue addOperation:operation];
    return operation;
}
- (void)cancelAllRendering { [_queue cancelAllOperations]; }
- (void)dealloc { [_queue cancelAllOperations]; [_queue release]; [_resourceBundle release]; [super dealloc]; }
@end
