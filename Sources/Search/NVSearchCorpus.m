#import "NVSearchCorpus.h"
#include "utf8proc-2.10.0/utf8proc.h"

NSData *NVSearchCanonicalUTF8(NSString *string, NVFZFCancel *cancel, NVFZFStatus *status) {
    *status = NVFZF_OK;
    if (nvfzf_cancel_is_set(cancel)) { *status = NVFZF_CANCELLED; return nil; }
    NSData *input = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (!input || [input length] > INT32_MAX) { *status = NVFZF_INVALID_INPUT; return nil; }
    if (nvfzf_cancel_is_set(cancel)) { *status = NVFZF_CANCELLED; return nil; }
    const unsigned char *bytes = [input bytes];
    NSUInteger byteLength = [input length];
    BOOL ascii = YES;
    for (NSUInteger i = 0; i < byteLength; ++i) {
        if (!(i & 4095) && nvfzf_cancel_is_set(cancel)) { *status = NVFZF_CANCELLED; return nil; }
        if (bytes[i] & 0x80) { ascii = NO; break; }
    }
    if (ascii) return input;
    utf8proc_uint8_t *output = NULL;
    utf8proc_ssize_t length = utf8proc_map([input bytes], [input length], &output, UTF8PROC_STABLE | UTF8PROC_COMPOSE);
    if (length < 0) { free(output); *status = length == UTF8PROC_ERROR_NOMEM ? NVFZF_OUT_OF_MEMORY : NVFZF_INVALID_INPUT; return nil; }
    if (nvfzf_cancel_is_set(cancel)) { free(output); *status = NVFZF_CANCELLED; return nil; }
    return [NSData dataWithBytesNoCopy:output length:(NSUInteger)length freeWhenDone:YES];
}

static NSComparisonResult NVSearchCompareUUID(NSData *left, NSData *right) {
    NSUInteger common = MIN([left length], [right length]);
    int comparison = common ? memcmp([left bytes], [right bytes], common) : 0;
    if (comparison) return comparison < 0 ? NSOrderedAscending : NSOrderedDescending;
    return [left length] < [right length] ? NSOrderedAscending : ([left length] > [right length] ? NSOrderedDescending : NSOrderedSame);
}

@implementation NVSearchLine
@synthesize text = _text, field = _field, range = _range, lineNumber = _lineNumber, preparedUTF8 = _preparedUTF8;
- (id)initWithText:(NSString *)text field:(NSString *)field range:(NSRange)range lineNumber:(NSUInteger)lineNumber bytes:(NSData *)bytes {
    if ((self = [super init])) {
        _text = [text copy]; _field = [field copy]; _range = range;
        _lineNumber = lineNumber; _preparedUTF8 = [bytes retain];
    }
    return self;
}
- (void)dealloc { [_text release]; [_field release]; [_preparedUTF8 release]; [super dealloc]; }
@end

@implementation NVSearchNoteSnapshot
@synthesize noteUUID = _noteUUID, title = _title, tags = _tags, source = _source, revision = _revision;
- (id)initWithNoteUUID:(NSData *)uuid title:(NSString *)title tags:(NSString *)tags source:(NSString *)source revision:(NSUInteger)revision {
    if ((self = [super init])) {
        if ([uuid length] != 16) { [self release]; return nil; }
        _noteUUID = [uuid copy]; _title = [(title ?: @"") copy]; _tags = [(tags ?: @"") copy];
        _source = [(source ?: @"") copy]; _revision = revision;
    }
    return self;
}
- (void)dealloc {
    [_noteUUID release]; [_title release]; [_tags release]; [_source release];
    [_lines release]; [super dealloc];
}
- (BOOL)hasSameContentAsSnapshot:(NVSearchNoteSnapshot *)other {
    return other && [_noteUUID isEqual:[other noteUUID]] && [_title isEqualToString:[other title]] &&
        [_tags isEqualToString:[other tags]] && [_source isEqualToString:[other source]];
}
- (NSArray *)lines { return _lines; }
- (BOOL)prepareLinesWithCancellation:(NVFZFCancel *)cancel status:(NVFZFStatus *)status {
    *status = NVFZF_OK;
    if (!_lines) _lines = [[NSMutableArray alloc] init];
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + 0.004;
    for (NSUInteger batch = 0; _lineField < 3 && batch < 64; ++batch) {
        if (nvfzf_cancel_is_set(cancel)) { *status = NVFZF_CANCELLED; return YES; }
        NSString *text = _lineField == 0 ? _title : (_lineField == 1 ? _tags : _source);
        if (_lineOffset >= [text length]) { ++_lineField; _lineOffset = _lineNumber = 0; continue; }
        NSUInteger end, contentsEnd;
        [text getLineStart:NULL end:&end contentsEnd:&contentsEnd forRange:NSMakeRange(_lineOffset, 0)];
        NSRange range = NSMakeRange(_lineOffset, contentsEnd - _lineOffset);
        if (range.length) {
            NSString *line = [text substringWithRange:range];
            NSData *bytes = NVSearchCanonicalUTF8(line, cancel, status);
            if (*status != NVFZF_OK) return YES;
            NSString *field = _lineField == 0 ? @"title" : (_lineField == 1 ? @"tags" : @"source");
            [_lines addObject:[[[NVSearchLine alloc] initWithText:line field:field range:range lineNumber:_lineNumber + 1 bytes:bytes] autorelease]];
        }
        _lineOffset = end; ++_lineNumber;
        if (CFAbsoluteTimeGetCurrent() >= deadline) break;
    }
    return _lineField == 3;
}
@end

@implementation NVSearchCorpus
@synthesize snapshots = _snapshots, revision = _revision;
- (id)init {
    if ((self = [super init])) { _snapshots = [[NSArray alloc] init]; _byUUID = [[NSMutableDictionary alloc] init]; _revision = 1; }
    return self;
}
- (void)dealloc { [_snapshots release]; [_byUUID release]; [super dealloc]; }
- (void)invalidate { ++_revision; }
- (NVSearchNoteSnapshot *)snapshotForUUID:(NSData *)uuid { return [_byUUID objectForKey:uuid]; }
- (BOOL)synchronizeWithSnapshots:(NSArray *)snapshots {
    NSMutableDictionary *next = [NSMutableDictionary dictionaryWithCapacity:[snapshots count]];
    for (NVSearchNoteSnapshot *snapshot in snapshots) {
        NVSearchNoteSnapshot *old = [_byUUID objectForKey:[snapshot noteUUID]];
        [next setObject:[old hasSameContentAsSnapshot:snapshot] ? old : snapshot forKey:[snapshot noteUUID]];
    }
    if ([next isEqualToDictionary:_byUUID]) return NO;
    NSArray *keys = [[next allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSData *left, NSData *right) {
        return NVSearchCompareUUID(left, right);
    }];
    NSMutableArray *ordered = [NSMutableArray arrayWithCapacity:[keys count]];
    for (NSData *uuid in keys) [ordered addObject:[next objectForKey:uuid]];
    [_snapshots release]; _snapshots = [ordered copy];
    [_byUUID release]; _byUUID = [next mutableCopy]; ++_revision;
    return YES;
}
- (BOOL)updateSnapshot:(NVSearchNoteSnapshot *)snapshot {
    if (!snapshot || [[_byUUID objectForKey:[snapshot noteUUID]] hasSameContentAsSnapshot:snapshot]) return NO;
    NSMutableArray *next = [_snapshots mutableCopy];
    NSUInteger low = 0, high = [next count];
    while (low < high) {
        NSUInteger mid = low + (high - low) / 2;
        if (NVSearchCompareUUID([[next objectAtIndex:mid] noteUUID], [snapshot noteUUID]) == NSOrderedAscending) low = mid + 1;
        else high = mid;
    }
    if (low < [next count] && [[[next objectAtIndex:low] noteUUID] isEqual:[snapshot noteUUID]]) [next replaceObjectAtIndex:low withObject:snapshot];
    else [next insertObject:snapshot atIndex:low];
    [(NSMutableDictionary *)_byUUID setObject:snapshot forKey:[snapshot noteUUID]];
    [_snapshots release]; _snapshots = [next copy]; [next release]; ++_revision;
    return YES;
}
- (BOOL)removeUUID:(NSData *)uuid {
    NVSearchNoteSnapshot *old = [_byUUID objectForKey:uuid];
    if (!old) return NO;
    NSMutableArray *next = [_snapshots mutableCopy]; [next removeObjectIdenticalTo:old];
    [(NSMutableDictionary *)_byUUID removeObjectForKey:uuid];
    [_snapshots release]; _snapshots = [next copy]; [next release]; ++_revision;
    return YES;
}
@end
