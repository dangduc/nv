#import "NVApplicationController.h"
//
//  PreviewController.m
//  Notation
//
//  Created by Christian Tietze on 15.10.10.
//  Copyright 2010

#import "PreviewController.h"
#import "AppController.h" // TODO for the defines only, can you get around that?
#import "AppController_Preview.h"
#import "NSString_MultiMarkdown.h"
#import "NSString_Markdown.h"
#import "NSString_Textile.h"
#import "NoteObject.h"
#import "BTTransparentScroller.h"
#import "NSFileManager_NV.h"
#import "NSFileManager+DirectoryLocations.h"

#define kDefaultMarkupPreviewVisible @"markupPreviewVisible"

@interface NSString (MIMEAdditions)
+ (NSString*)MIMEBoundary;
+ (NSString*)multipartMIMEStringWithDictionary:(NSDictionary*)dict;
@end

@implementation NSString (MIMEAdditions)
//this returns a unique boundary which is used in constructing the multipart MIME body of the POST request
+ (NSString*)MIMEBoundary
{
    static NSString* MIMEBoundary = nil;
    if(!MIMEBoundary)
        MIMEBoundary = [[NSString alloc] initWithFormat:@"----_=_nvALT_%@_=_----",[[NSProcessInfo processInfo] globallyUniqueString]];
    return MIMEBoundary;
}
//this create a correctly structured multipart MIME body for the POST request from a dictionary
+ (NSString*)multipartMIMEStringWithDictionary:(NSDictionary*)dict
{
    NSMutableString* result = [NSMutableString string];
    for (NSString* key in dict)
    {
        [result appendFormat:@"--%@\nContent-Disposition: form-data; name=\"%@\"\n\n%@\n",[NSString MIMEBoundary],key,[dict objectForKey:key]];
    }
    [result appendFormat:@"\n--%@--\n",[NSString MIMEBoundary]];
    return result;
}
@end

// JavaScript owns its logging bridge. It must not retain the preview controller.
@interface NVPreviewScriptLogger : NSObject
- (void)logJavaScriptString:(NSString *)text;
@end

@implementation NVPreviewScriptLogger
+ (NSString *)webScriptNameForSelector:(SEL)selector {
    return selector == @selector(logJavaScriptString:) ? @"log" : nil;
}
+ (BOOL)isSelectorExcludedFromWebScript:(SEL)selector {
    return selector != @selector(logJavaScriptString:);
}
- (void)logJavaScriptString:(NSString *)text {
    NSLog(@"JavaScript: %@", text);
}
@end

@implementation PreviewController

@synthesize preview;
@synthesize isPreviewOutdated;
@synthesize isPreviewSticky;

+(void)initialize
{
    NSDictionary *appDefaults = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:NO]
                                                            forKey:kDefaultMarkupPreviewVisible];

    [[NSUserDefaults standardUserDefaults] registerDefaults:appDefaults];
    /* Initialize webInspector. */
    [[NSUserDefaults standardUserDefaults] setBool:TRUE forKey:@"WebKitDeveloperExtras"];
    [[NSUserDefaults standardUserDefaults] synchronize];

}

- (id)initWithBrowserController:(AppController *)controller
{
    if ((self = [super initWithWindowNibName:@"MarkupPreview" owner:self])) {
        browserController = controller;
        self.isPreviewOutdated = YES;
        self.isPreviewSticky = NO;
        // Load the nib before assigning its views to the popover content controllers.
        NSWindow *previewWindow = [self window];
        BOOL showPreviewWindow = [[NSUserDefaults standardUserDefaults] boolForKey:kDefaultMarkupPreviewVisible];
        if (showPreviewWindow) {
            [previewWindow orderFront:self];
        }

        [tabView selectTabViewItem:[tabView tabViewItemAtIndex:0]];

        NSRect shCon = [shareConfirmation visibleRect];
        shCon.origin.x = shCon.size.width - 130;
        shCon.origin.y = 12;
        shCon.size.width = 110;
        shCon.size.height = 28;
        shareConfirm = [[NSButton alloc] initWithFrame:shCon];
        shCon.origin.x = 20;
        shareCancel = [[NSButton alloc] initWithFrame:shCon];
        [shareConfirm setTitle:@"Yes"];
        [shareConfirm setBezelStyle:NSRoundedBezelStyle];
        [shareConfirm setTarget:self];
        [shareConfirm setAction:@selector(shareNote:)];
        [shareCancel setTitle:@"No, thanks"];
        [shareCancel setBezelStyle:NSRoundedBezelStyle];
        [shareCancel setTarget:self];
        [shareCancel setAction:@selector(cancelShare:)];
        [shareConfirmation addSubview:shareCancel];
        [shareConfirmation addSubview:shareConfirm];

        shCon = [shareNotification visibleRect];
        shCon.size.width = 150;
        shCon.size.height = 28;
        shCon.origin.x = (NSWidth([shareNotification bounds]) - shCon.size.width) / 2;
        shCon.origin.y = 12;
        viewOnWebButton = [[NSButton alloc] initWithFrame:shCon];
        [viewOnWebButton setTitle:@"View in Browser"];
        [viewOnWebButton setBezelStyle:NSRoundedBezelStyle];
        [viewOnWebButton setTarget:self];
        [viewOnWebButton setAction:@selector(openShareURL:)];
        [shareNotification addSubview:viewOnWebButton];
        NSViewController *confirmationContent = [[NSViewController alloc] initWithNibName:nil bundle:nil];
        [confirmationContent setView:shareConfirmation];
        confirmationPopover = [[NSPopover alloc] init];
        [confirmationPopover setContentViewController:confirmationContent];
        [confirmationPopover setBehavior:NSPopoverBehaviorTransient];
        [confirmationPopover setContentSize:[shareConfirmation frame].size];
        [confirmationContent release];

        NSViewController *shareContent = [[NSViewController alloc] initWithNibName:nil bundle:nil];
        [shareContent setView:shareNotification];
        sharePopover = [[NSPopover alloc] init];
        [sharePopover setContentViewController:shareContent];
        [sharePopover setBehavior:NSPopoverBehaviorTransient];
        [sharePopover setContentSize:[shareNotification frame].size];
        [shareContent release];
    }
    return self;
}

-(void)awakeFromNib
{
    cssString = [[[self class] css] retain];
    htmlString = [[[self class] html] retain];
    lastNote = [[browserController selectedNoteObject] retain];
    [sourceView setTextContainerInset:NSMakeSize(10.0,12.0)];
    NSScrollView *scrlView=[sourceView enclosingScrollView];
    if (!IsLionOrLater) {
        NSRect vsRect=[[scrlView verticalScroller]frame];
        BTTransparentScroller *theScroller=[[BTTransparentScroller alloc]initWithFrame:vsRect];
        [scrlView setVerticalScroller:theScroller];
        [theScroller release];
    }
    [scrlView setScrollsDynamically:YES];
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
    if (IsLionOrLater) {
        [scrlView setHorizontalScrollElasticity:NSScrollElasticityNone];
        [scrlView setVerticalScrollElasticity:NSScrollElasticityAutomatic];
        [scrlView setScrollerStyle:NSScrollerStyleOverlay];
    }
#endif
}

//this is called as soon as the script environment is ready in the webview
- (void)webView:(WebView *)sender didClearWindowObject:(WebScriptObject *)windowScriptObject forFrame:(WebFrame *)frame
{
    NVPreviewScriptLogger *logger = [[[NVPreviewScriptLogger alloc] init] autorelease];
    [windowScriptObject setValue:logger forKey:@"Cocoa"];
}

// Above webView methods from <http://stackoverflow.com/questions/2288582/embedded-webkit-script-callbacks-how/2293305#2293305>

- (void)webView:(WebView *)sender decidePolicyForNavigationAction:(NSDictionary *)actionInformation request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener {
    NSString *targetURL = [[request URL] scheme];

    if (![[actionInformation objectForKey:@"WebActionNavigationTypeKey"] isEqualToNumber:[NSNumber numberWithInt:5]]) {
        [[NSWorkspace sharedWorkspace] openURL:[request URL]];
        [listener ignore];
    } else {
        [listener use];
    }
}

- (void)webView:(WebView *)sender decidePolicyForNewWindowAction:(NSDictionary *)actionInformation request:(NSURLRequest *)request newFrameName:(NSString *)frameName decisionListener:(id<WebPolicyDecisionListener>)listener {
    NSLog(@"NEW WIN ACTION SENDER: %@",sender);
    [[NSWorkspace sharedWorkspace] openURL:[actionInformation objectForKey:WebActionOriginalURLKey]];
    [listener ignore];
}

-(void)requestPreviewUpdate:(NSNotification *)notification
{
    AppController *app = [notification object];
    NSString *rawString = [app noteContent];
    if (app == [[NVApplicationController sharedController] activeBrowser]) {
        NSPasteboard *pb = [NSPasteboard pasteboardWithName:@"mkStreamingPreview"];
        [pb clearContents];
        [pb setString:rawString ?: @"" forType:(NSString *)kUTTypeUTF8PlainText];
    }

    if (![[self window] isVisible]) {
        self.isPreviewOutdated = YES;
        return;
    }

    if (self.isPreviewSticky) {
        return;
    }


    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(preview:) object:app];

    [self performSelector:@selector(preview:) withObject:app afterDelay:0.05];
}

- (BOOL)previewIsVisible{
    return [[self window] isVisible];
}

-(void)togglePreview:(id)sender
{

    NSWindow *wnd = [self window];
    if ([wnd isVisible]) {
        [self cancelShare:self];
        [self closeShareURLView];
        //      // TODO: should the "stuck" note remain stuck when preview is closed?
        //      if (self.isPreviewSticky)
        //        [self makePreviewNotSticky:self];
        [wnd orderOut:self];
    } else {
        if (self.isPreviewOutdated) {
            // TODO high coupling; too many assumptions on architecture:
            [self performSelector:@selector(preview:) withObject:browserController afterDelay:0.0];
        }
        [tabView selectTabViewItem:[tabView tabViewItemAtIndex:0]];
        [tabSwitcher setTitle:@"View Source"];

        [wnd orderFront:self];
    }

    // save visibility to defaults
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:[wnd isVisible]]
                                              forKey:kDefaultMarkupPreviewVisible];
}

- (void)close
{
    [self cancelShare:self];
    [self closeShareURLView];
    [super close];
}

-(void)windowWillClose:(NSNotification *)notification
{
    [self cancelShare:self];
    [self closeShareURLView];
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:NO]
                                              forKey:kDefaultMarkupPreviewVisible];
    NSMenu *previewMenu = [[[NSApp mainMenu] itemWithTitle:@"Preview"] submenu];
    [[previewMenu itemWithTitle:@"Toggle Preview Window"]setState:0];
}

+(NSString*)css {
    NSFileManager *mgr = [NSFileManager defaultManager];
    NSString *folder = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSString *cssFileName = @"custom.css";
    NSString *customCSSPath = [folder stringByAppendingPathComponent: cssFileName];
    if ([mgr fileExistsAtPath:customCSSPath]) {
        return [NSString stringWithContentsOfFile:customCSSPath
                                         encoding:NSUTF8StringEncoding
                                            error:NULL];
    } else {
        NSString *cssPath = [[NSBundle mainBundle] pathForResource:@"custom" ofType:@"css" inDirectory:nil];
        return [NSString stringWithContentsOfFile:cssPath encoding:NSUTF8StringEncoding error:nil];
    }

    //	if (![mgr fileExistsAtPath:customCSSPath]) {
    //		[[self class] createCustomFiles];
    //	}


}

+(NSString*)html {
    NSFileManager *mgr = [NSFileManager defaultManager];

    NSString *folder = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSString *htmlFileName = @"template.html";
    NSString *customHTMLPath = [folder stringByAppendingPathComponent: htmlFileName];
    if ([mgr fileExistsAtPath:customHTMLPath]) {
        return [NSString stringWithContentsOfFile:customHTMLPath
                                         encoding:NSUTF8StringEncoding
                                            error:NULL];
    } else {
        NSString *htmlPath = [[NSBundle mainBundle] pathForResource:@"template" ofType:@"html" inDirectory:nil];
        return [NSString stringWithContentsOfFile:htmlPath encoding:NSUTF8StringEncoding error:nil];
    }
    //	if (![mgr fileExistsAtPath:customHTMLPath]) {
    //		[[self class] createCustomFiles];
    //	}
}

-(void)preview:(id)object
{
    if (self.isPreviewSticky) {
        return;
    }
    NSString *lastScrollPosition = [preview stringByEvaluatingJavaScriptFromString:@"document.getElementsByTagName('body')[0].scrollTop"];
    //	NSString *lastScrollPosition = [[preview windowScriptObject] evaluateWebScript:@"document.getElementsByTagName('body')[0].scrollTop"];
    AppController *app = object;
    NSString *rawString = [app noteContent];

    SEL mode = [self markupProcessorSelector:[app currentPreviewMode]];
    NSString *processedString = [NSString performSelector:mode withObject:rawString];
    NSString *previewString = processedString;
    NSMutableString *outputString = [NSMutableString stringWithString:(NSString *)htmlString];
    NSString *noteTitle =  ([app selectedNoteObject]) ? [NSString stringWithFormat:@"%@",titleOfNote([app selectedNoteObject])] : @"";

    if (lastNote == [app selectedNoteObject]) {
        NSString *restoreScrollPosition = [NSString stringWithFormat:@"\n<script>var body = document.getElementsByTagName('body')[0],oldscroll = %@;body.scrollTop = oldscroll;</script>",lastScrollPosition];
        previewString = [processedString stringByAppendingString:restoreScrollPosition];
    } else {
        [cssString release];
        [htmlString release];
        cssString = [[[self class] css] retain];
        htmlString = [[[self class] html] retain];
        [lastNote release];
        lastNote = [[app selectedNoteObject] retain];
    }
    NSString *nvSupportPath = [[NSFileManager defaultManager] applicationSupportDirectory];

    [outputString replaceOccurrencesOfString:@"{%support%}" withString:nvSupportPath options:0 range:NSMakeRange(0, [outputString length])];
    [outputString replaceOccurrencesOfString:@"{%title%}" withString:noteTitle options:0 range:NSMakeRange(0, [outputString length])];
    [outputString replaceOccurrencesOfString:@"{%content%}" withString:previewString options:0 range:NSMakeRange(0, [outputString length])];
    [outputString replaceOccurrencesOfString:@"{%style%}" withString:cssString options:0 range:NSMakeRange(0, [outputString length])];

    [[preview mainFrame] loadHTMLString:outputString baseURL:nil];
    [preview stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"var body = document.getElementsByTagName('body')[0],oldscroll = %@;body.scrollTop = oldscroll;",lastScrollPosition]];
    [[self window] setTitle:noteTitle];

    [sourceView replaceCharactersInRange:NSMakeRange(0, [[sourceView string] length]) withString:processedString];
    self.isPreviewOutdated = NO;
}

-(SEL)markupProcessorSelector:(NSInteger)previewMode
{
    if (previewMode == MarkdownPreview) {
        previewMode = MultiMarkdownPreview;
        return @selector(stringWithProcessedMultiMarkdown:);
    } else if (previewMode == MultiMarkdownPreview) {
        return @selector(stringWithProcessedMultiMarkdown:);
    } else if (previewMode == TextilePreview) {
        return @selector(stringWithProcessedTextile:);
    }

    return nil;
}

+ (void) createCustomFiles
{
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSString *folder = [[NSFileManager defaultManager] applicationSupportDirectory];
    if ([fileManager fileExistsAtPath: folder] == NO)
    {
        [fileManager createFolderAtPath:folder];
        //				[fileManager createDirectoryAtPath: folder attributes: nil];

    }

    NSString *cssFileName = @"custom.css";
    NSString *cssFile = [folder stringByAppendingPathComponent: cssFileName];

    if ([fileManager fileExistsAtPath:cssFile] == NO)
    {
        NSString *cssPath = [[NSBundle mainBundle] pathForResource:@"customclean" ofType:@"css" inDirectory:nil];
        NSString *cssString = [NSString stringWithContentsOfFile:cssPath encoding:NSUTF8StringEncoding error:nil];
        NSData *cssData = [NSData dataWithBytes:[cssString UTF8String] length:[cssString length]];
        [fileManager createFileAtPath:cssFile contents:cssData attributes:nil];
    }

    NSString *htmlFileName = @"template.html";
    NSString *htmlFile = [folder stringByAppendingPathComponent: htmlFileName];

    if ([fileManager fileExistsAtPath:htmlFile] == NO)
    {
        NSString *htmlPath = [[NSBundle mainBundle] pathForResource:@"templateclean" ofType:@"html" inDirectory:nil];
        NSString *htmlString = [NSString stringWithContentsOfFile:htmlPath encoding:NSUTF8StringEncoding error:nil];
        NSData *htmlData = [NSData dataWithBytes:[htmlString UTF8String] length:[htmlString length]];
        [fileManager createFileAtPath:htmlFile contents:htmlData attributes:nil];
    }

}

- (NSString *)urlEncodeValue:(NSString *)str
{
    NSString *result = (NSString *) CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)str, NULL, CFSTR("?=&+"), kCFStringEncodingUTF8);
    return [result autorelease];
}

-(IBAction)makePreviewSticky:(id)sender
{
    self.isPreviewSticky = YES;
    //  [[preview window] setTitle:@"Locked"];
    [stickyPreviewButton setState:YES];
    [stickyPreviewButton setToolTip:@"Return the preview to normal functionality."];
    [stickyPreviewButton setAction:@selector(makePreviewNotSticky:)];
    [shareButton setEnabled:NO];
    [saveButton setEnabled:NO];
    [[self window] setHidesOnDeactivate:NO];
}

-(IBAction)makePreviewNotSticky:(id)sender
{
    self.isPreviewSticky = NO;
    [[preview window] setTitle:@"Preview"];
    [stickyPreviewButton setState:NO];
    [stickyPreviewButton setToolTip:@"Maintain current note in Preview, even if you switch to other notes."];
    [stickyPreviewButton setAction:@selector(makePreviewSticky:)];
    [shareButton setEnabled:YES];
    [saveButton setEnabled:YES];
    self.isPreviewOutdated = YES;
    [self performSelector:@selector(preview:) withObject:browserController afterDelay:0.0];
    [[self window] setHidesOnDeactivate:YES];
}

-(IBAction)printPreview:(id)sender
{
    NSTabViewItem *selectedTab=[tabView selectedTabViewItem];
    //1 is webview   2 is source view
    if ([selectedTab.identifier integerValue]==1) {
        [tabView selectNextTabViewItem:self];
    }
    NSPrintInfo* printInfo = [NSPrintInfo sharedPrintInfo];

    [printInfo setHorizontallyCentered:YES];
    [printInfo setVerticallyCentered:NO];
    NSPrintOperation *printOp=[[[preview mainFrame] frameView] printOperationWithPrintInfo:printInfo];
    [printOp runOperationModalForWindow:tabView.window delegate:self didRunSelector:@selector(printOperationDidRun:success:contextInfo:) contextInfo:selectedTab];
}

- (void)printOperationDidRun:(NSPrintOperation *)printOperation  success:(BOOL)success  contextInfo:(void *)contextInfo{
    NSTabViewItem *selTab=(NSTabViewItem *)contextInfo;
    if (selTab&&(tabView.selectedTabViewItem!=selTab)) {
        [tabView selectTabViewItem:selTab];
    }
}

-(IBAction)shareNote:(id)sender
{
    AppController *app = browserController;
    NSString *noteTitle = [NSString stringWithFormat:@"%@",titleOfNote([app selectedNoteObject])];
    NSString *rawString = [app noteContent];
    SEL mode = [self markupProcessorSelector:[app currentPreviewMode]];
    NSString *processedString = [NSString performSelector:mode withObject:rawString];


    NSMutableURLRequest *request = [[NSMutableURLRequest alloc]
                                    initWithURL:
                                    [NSURL URLWithString:@"http://peg.gd/nvapi.php"]];
    [request setHTTPMethod:@"POST"];
    [request addValue:@"8bit" forHTTPHeaderField:@"Content-Transfer-Encoding"];
    [request addValue: [NSString stringWithFormat:@"multipart/form-data; boundary=%@",[NSString MIMEBoundary]] forHTTPHeaderField: @"Content-Type"];
    NSDictionary* postData = [NSDictionary dictionaryWithObjectsAndKeys:
                              @"8c4205ec33d8f6caeaaaa0c10a14138c", @"key",
                              noteTitle, @"title",
                              processedString, @"body",
                              nil];
    [request setHTTPBody: [[NSString multipartMIMEStringWithDictionary: postData] dataUsingEncoding: NSUTF8StringEncoding]];
    NSHTTPURLResponse * response = nil;
    NSError * error = nil;
    NSData * responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    NSString * responseString = [[[NSString alloc] initWithData:responseData encoding:NSASCIIStringEncoding] autorelease];
    NSLog(@"RESPONSE STRING: %@", responseString);
    NSLog(@"%ld",(long)response.statusCode);
    if (response.statusCode == 200) {
        [self showShareURL:responseString isError:NO];
    } else {
        [self showShareURL:@"Error connecting" isError:YES];
    }

    [request release];

}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    [receivedData setLength:0];
}


- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [receivedData appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    NSLog(@"Succeeded! Received %lu bytes of data",(unsigned long)[receivedData length]);

    NSString * responseString = [[[NSString alloc] initWithData:receivedData encoding:NSASCIIStringEncoding] autorelease];
    NSLog(@"RESPONSE STRING: %@", responseString);
    [receivedData release];
}

- (void)savePanelDidEnd:(NSSavePanel *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo {
    if (returnCode == NSFileHandlingPanelOKButton) {

        AppController *app = browserController;
        NSString *rawString = [app noteContent];
        NSString *processedString = [[[NSString alloc] init] autorelease];

        if ([app currentPreviewMode] == MarkdownPreview) {
            processedString = [NSString stringWithProcessedMarkdown:rawString];
        } else if ([app currentPreviewMode] == MultiMarkdownPreview) {
            processedString = ( [includeTemplate state] == NSOnState ) ? [NSString documentWithProcessedMultiMarkdown:rawString] : [NSString xhtmlWithProcessedMultiMarkdown:rawString];
        } else if ([app currentPreviewMode] == TextilePreview) {
            processedString = ( [includeTemplate state] == NSOnState ) ? [NSString documentWithProcessedTextile:rawString] : [NSString xhtmlWithProcessedTextile:rawString];
        }
        NSURL *file = [sheet URL];
        NSError *error;
        [processedString writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:&error];
    }
}

-(IBAction)saveHTML:(id)sender
{
    if (!accessoryView) {
        if (![NSBundle loadNibNamed:@"SaveHTMLPreview" owner:self]) {
            NSLog(@"Failed to load SaveHTMLPreview.nib");
            NSBeep();
            return;
        }

    }
    // TODO high coupling; too many assumptions on architecture:
    AppController *app = browserController;

    NSSavePanel *savePanel = [NSSavePanel savePanel];
    [savePanel setAccessoryView:accessoryView];
    [savePanel setCanCreateDirectories:YES];
    [savePanel setCanSelectHiddenExtension:YES];

    NSArray *fileTypes = [[NSArray alloc] initWithObjects:@"html",@"xhtml",@"htm",nil];
    [savePanel setAllowedFileTypes:fileTypes];


    NSString *rawString = [app noteContent];
    NSString *xhtmlOutput = [NSString xhtmlWithProcessedMultiMarkdown:rawString];
    if ([xhtmlOutput hasPrefix:@"<?xml version="]) {
        [includeTemplate setState:0];
        [includeTemplate setEnabled:NO];
        [templateNote setStringValue:@"Template embed unavailable because your note will render as a full XHTML document"];
    } else {
        [includeTemplate setEnabled:YES];
        [templateNote setStringValue:@"Select this to embed the ouput within your current preview HTML and CSS"];
    }

    NSString *noteTitle =  ([app selectedNoteObject]) ? [NSString stringWithFormat:@"%@",titleOfNote([app selectedNoteObject])] : @"";
    //	[savePanel beginSheetForDirectory:nil file:noteTitle modalForWindow:[self window] modalDelegate:self didEndSelector:@selector(savePanelDidEnd:returnCode:contextInfo:) contextInfo:nil];
    savePanel.nameFieldStringValue=noteTitle;
    [savePanel beginSheetModalForWindow:[self window] completionHandler:^(NSInteger returnCode) {
        if (returnCode == NSFileHandlingPanelOKButton) {
            NSString *processedString = [[[NSString alloc] init] autorelease];

            if ([app currentPreviewMode] == MarkdownPreview) {
                processedString = [NSString stringWithProcessedMarkdown:rawString];
            } else if ([app currentPreviewMode] == MultiMarkdownPreview) {
                processedString = ( [includeTemplate state] == NSOnState ) ? [NSString documentWithProcessedMultiMarkdown:rawString] : [NSString xhtmlWithProcessedMultiMarkdown:rawString];
            } else if ([app currentPreviewMode] == TextilePreview) {
                processedString = ( [includeTemplate state] == NSOnState ) ? [NSString documentWithProcessedTextile:rawString] : [NSString xhtmlWithProcessedTextile:rawString];
            }
            NSURL *file = [savePanel URL];
            NSError *error;
            [processedString writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:&error];
        }
    }];
    [fileTypes release];

}

-(IBAction)switchTabs:(id)sender
{

    if ([tabView indexOfTabViewItem:[tabView selectedTabViewItem]] == 0) {
        [tabSwitcher setTitle:@"View Preview"];
        [tabView selectTabViewItem:[tabView tabViewItemAtIndex:1]];
    } else {
        [tabSwitcher setTitle:@"View Source"];
        [tabView selectTabViewItem:[tabView tabViewItemAtIndex:0]];
    }
}

- (IBAction)shareAsk:(id)sender
{
    if ([confirmationPopover isShown]) {
        [self cancelShare:sender];
    } else if ([sharePopover isShown]) {
        [self hideShareURL:sender];
    } else {
        [self closeShareURLView];
        [confirmationPopover showRelativeToRect:[shareButton bounds] ofView:shareButton preferredEdge:NSMaxYEdge];
    }
}

- (void)showShareURL:(NSString *)url isError:(BOOL)isError
{
    [self cancelShare:self];
    [self closeShareURLView];
    [viewOnWebButton setHidden:isError];
    if (isError) {
        [urlTextField setStringValue:url ?: @"Error connecting"];
    } else {
        shareURL = [url copy];
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb declareTypes:@[NSStringPboardType] owner:nil];
        [pb setString:shareURL forType:NSStringPboardType];
        [urlTextField setStringValue:[NSString stringWithFormat:@"Copied %@ to clipboard", shareURL]];
    }
    if ([[self window] isVisible]) {
        [sharePopover showRelativeToRect:[shareButton bounds] ofView:shareButton preferredEdge:NSMaxYEdge];
    }
}

- (void)closeShareURLView
{
    [sharePopover close];
    [shareURL release];
    shareURL = nil;
}

- (IBAction)hideShareURL:(id)sender
{
    [self closeShareURLView];
}

- (IBAction)cancelShare:(id)sender
{
    [confirmationPopover close];
}

- (IBAction)openShareURL:(id)sender
{
    if (shareURL) [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:shareURL]];
    [self closeShareURLView];
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self cancelShare:self];
    [self closeShareURLView];
    [confirmationPopover release];
    [sharePopover release];
    [preview release];
    [htmlString release];
    [cssString release];
    [lastNote release];
    [viewOnWebButton release];
    [shareCancel release];
    [shareConfirm release];
    [super dealloc];
}

@end
