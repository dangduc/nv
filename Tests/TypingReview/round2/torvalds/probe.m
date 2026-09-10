#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "NVSourceAnalysis.h"
NSString * const NVNoteWordCountDidChangeNotification = @"ProbeWordCount";
#include "flags.inc"
static NSUInteger checks, cases, repeated, unicodeCases, editCases;
static uint64_t state = 0x6b8b4567327b23c6ULL;
static uint32_t Random(void) { state ^= state << 13; state ^= state >> 7; state ^= state << 17; return (uint32_t)state; }
static void Check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL case=%lu seed_state=%llu: %s\n", cases, state, message.UTF8String); exit(1); }
}
@interface FixtureNote : NSObject
- (NSString *)sourceSyntaxIdentifier;
@end
@implementation FixtureNote
- (NSString *)sourceSyntaxIdentifier { return @"plain"; }
@end
@interface FixtureSession : NSObject {
@public
    BOOL closed;
    uint64_t sourceGeneration, wordCountGeneration;
    NSTextStorage *textStorage;
    FixtureNote *note;
    NVSourceAnalysis *sourceAnalysis;
    NSHashTable *wordCountClients;
    NSUInteger wordCount;
}
@end
@implementation FixtureSession
#include "publication.inc"
@end
static NSDictionary *Run(NSUInteger location, NSUInteger length, NSUInteger target) {
    return @{@"range":[NSValue valueWithRange:NSMakeRange(location,length)],
             @"url":[NSURL URLWithString:[NSString stringWithFormat:@"https://example.invalid/%lu",target]]};
}
static NSArray *ReadRuns(NSAttributedString *storage) {
    NSMutableArray *runs = [NSMutableArray array];
    [storage enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0,storage.length) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
        if (value) [runs addObject:@{@"range":[NSValue valueWithRange:range],@"url":value}];
    }];
    return runs;
}
static void PutRuns(NSMutableAttributedString *storage, NSArray *runs) {
    for (NSDictionary *run in runs) [storage addAttribute:NSLinkAttributeName value:run[@"url"] range:[run[@"range"] rangeValue]];
}
static NSArray *RandomRuns(NSString *source) {
    NSMutableAttributedString *decorated = [[[NSMutableAttributedString alloc] initWithString:source] autorelease];
    NSUInteger position = 0;
    while (position < source.length) {
        NSUInteger length = MIN(1 + Random()%12, source.length-position);
        if (Random()%3) PutRuns(decorated,@[Run(position,length,Random()%4)]);
        position += length;
    }
    return ReadRuns(decorated); // Canonical source-ordered non-overlapping input, as the production extractor supplies.
}
static void Exercise(NSString *source, NSArray *oldRuns, NSArray *newRuns, BOOL characterEdit, NSString *label) {
    cases++;
    FixtureSession *session = [[FixtureSession alloc] init];
    session->sourceGeneration = 9;
    session->note = [[FixtureNote alloc] init];
    session->textStorage = [[NSTextStorage alloc] initWithString:source attributes:@{@"ProbeKeep":@"base"}];
    for (NSUInteger i=0; i<source.length; i+=3)
        [session->textStorage addAttribute:@"ProbeKeep" value:@(i%5) range:NSMakeRange(i,MIN((NSUInteger)2,source.length-i))];
    PutRuns(session->textStorage,oldRuns);
    if (characterEdit && source.length) {
        // Native NSTextStorage must transform inherited old attributes before publication.
        NSUInteger start = Random()%source.length, length = Random()%(source.length-start+1);
        [session->textStorage replaceCharactersInRange:NSMakeRange(start,length) withString:@"🪻é中"];
        newRuns = RandomRuns([session->textStorage string]); editCases++;
    }
    NSTextStorage *expected = [[NSTextStorage alloc] initWithAttributedString:session->textStorage];
    [expected removeAttribute:NSLinkAttributeName range:NSMakeRange(0,expected.length)];
    PutRuns(expected,newRuns); // Independent full-replacement oracle.
    NSDictionary *result = @{@"generation":@9,@"syntax":@"plain",@"linkRuns":newRuns};
    NVSetSourceLinksCurrent(session->textStorage,NO);
    [session sourceAnalysis:nil didFinish:result];
    Check([[session->textStorage string] isEqualToString:[expected string]], @"characters preserved");
    Check([ReadRuns(session->textStorage) isEqual:ReadRuns(expected)], label);
    for (NSUInteger i=0;i<expected.length;i++)
        Check([[session->textStorage attribute:@"ProbeKeep" atIndex:i effectiveRange:NULL] isEqual:[expected attribute:@"ProbeKeep" atIndex:i effectiveRange:NULL]], @"unrelated application attributes preserved");
    Check(NVSourceLinksAreCurrent(session->textStorage),@"accepted result marks links current");
    __block NSUInteger edits = 0;
    id observation = [[NSNotificationCenter defaultCenter] addObserverForName:NSTextStorageDidProcessEditingNotification object:session->textStorage queue:nil usingBlock:^(NSNotification *n) { edits++; }];
    [session sourceAnalysis:nil didFinish:result]; repeated++;
    Check(edits==0,@"repeated canonical publication causes no storage edit");
    Check([ReadRuns(session->textStorage) isEqual:ReadRuns(expected)],@"repeat equals full-replacement oracle");
    for (NSDictionary *obsolete in @[@{@"generation":@8,@"syntax":@"plain",@"linkRuns":@[]},@{@"generation":@9,@"syntax":@"org",@"linkRuns":@[]}]) {
        [session sourceAnalysis:nil didFinish:obsolete];
        Check(edits==0 && [ReadRuns(session->textStorage) isEqual:ReadRuns(expected)],@"obsolete generation or syntax preserves accepted state");
    }
    session->closed=YES;
    [session sourceAnalysis:nil didFinish:@{@"generation":@9,@"syntax":@"plain",@"linkRuns":@[]}];
    Check(edits==0 && [ReadRuns(session->textStorage) isEqual:ReadRuns(expected)],@"closed session ignores publication");
    [[NSNotificationCenter defaultCenter] removeObserver:observation];
    [session->textStorage release]; [session->note release]; [session release]; [expected release];
}
int main(void) { @autoreleasepool {
    NSString *source = @"abcdefghijklmnopqrstuvwxyz0123456789";
    Exercise(source,@[Run(2,10,0),Run(18,6,1)],@[Run(4,17,2)],NO,@"overlap two old runs");
    Exercise(source,@[Run(0,36,0)],@[Run(0,1,1),Run(2,32,2),Run(35,1,1)],NO,@"split and both range edges");
    Exercise(source,@[Run(0,1,1),Run(2,32,2),Run(35,1,1)],@[Run(0,36,0)],NO,@"merge and full range");
    Exercise(@"",@[],@[],NO,@"empty storage");
    Exercise(@"x",@[Run(0,1,0)],@[],NO,@"one-character deletion");
    Exercise(@"🪻é中",@[Run(0,1,0),Run(1,1,1)],@[Run(0,2,2),Run(2,3,1)],NO,@"UTF-16 surrogate and combining range boundaries");
    NSArray *atoms = @[@"a",@" ",@"\n",@"🪻",@"é",@"中",@"\r\n",@"👩‍💻"];
    for (NSUInteger i=0;i<12000;i++) { @autoreleasepool {
        NSMutableString *generated = [NSMutableString string];
        NSUInteger count=Random()%48;
        for (NSUInteger j=0;j<count;j++) [generated appendString:atoms[Random()%atoms.count]];
        unicodeCases++;
        NSArray *oldRuns=RandomRuns(generated);
        NSArray *newRuns=(i%6==0)?oldRuns:RandomRuns(generated);
        Exercise(generated,oldRuns,newRuns,i%3==0,@"randomized ordered merge equals native full replacement");
    }}
    printf("PASS: %lu cases; %lu checks; %lu Unicode cases; %lu native character edits; %lu repeated publications\n",cases,checks,unicodeCases,editCases,repeated);
} return 0; }
