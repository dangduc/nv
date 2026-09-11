#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
#import "NVSourceTypesetter.h"
#include <time.h>
#include <stdint.h>

static NSUInteger Checks, GlyphCalls, Glyphs, Composed, Mallocs, MallocBytes, Frees, Adjusted;
static NSUInteger Creates, SnapshotChars, Suggests, Lines, Tokens;
static double DelegateMs;
static void Check(BOOL condition, NSString *message) {
    Checks++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static double Now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
static void Reset(void) { GlyphCalls=Glyphs=Composed=Mallocs=MallocBytes=Frees=Adjusted=Creates=SnapshotChars=Suggests=Lines=Tokens=0; DelegateMs=0; }
static NSRange CountComposed(NSString *source, NSUInteger index) { Composed++; return [source rangeOfComposedCharacterSequenceAtIndex:index]; }
static void *CountMalloc(size_t bytes) { Mallocs++; MallocBytes+=bytes; return malloc(bytes); }
static void CountFree(void *buffer) { Frees++; free(buffer); }
static CTTypesetterRef CountCreate(CFAttributedStringRef text) { Creates++; SnapshotChars+=CFAttributedStringGetLength(text); return CTTypesetterCreateWithAttributedString(text); }
static CFIndex CountSuggest(CTTypesetterRef t, CFIndex index, double width, double offset) { Suggests++; return CTTypesetterSuggestClusterBreakWithOffset(t,index,width,offset); }
static CTLineRef CountLine(CTTypesetterRef t, CFRange range, double offset) { Lines++; return CTTypesetterCreateLineWithOffset(t,range,offset); }
static CFStringTokenizerTokenType CountToken(CFStringTokenizerRef t) { Tokens++; return CFStringTokenizerAdvanceToNextToken(t); }
#ifdef COUNTS
#define CTTypesetterCreateWithAttributedString CountCreate
#define CTTypesetterSuggestClusterBreakWithOffset CountSuggest
#define CTTypesetterCreateLineWithOffset CountLine
#define CFStringTokenizerAdvanceToNextToken CountToken
#endif
@TYPESETTER@
#undef CTTypesetterCreateWithAttributedString
#undef CTTypesetterSuggestClusterBreakWithOffset
#undef CTTypesetterCreateLineWithOffset
#undef CFStringTokenizerAdvanceToNextToken
#ifdef COUNTS
#define malloc CountMalloc
#define free CountFree
#endif
@interface BaseDelegate : NSObject <NSLayoutManagerDelegate> @end
@implementation BaseDelegate
@BASE_DELEGATE@
@end
@interface CandidateDelegate : NSObject <NSLayoutManagerDelegate> @end
@implementation CandidateDelegate
@CANDIDATE_DELEGATE@
@end
#undef malloc
#undef free
@interface Observer : NSObject <NSLayoutManagerDelegate> { id actual; }
- (id)initCandidate:(BOOL)candidate;
@end
@implementation Observer
- (id)initCandidate:(BOOL)candidate { if ((self=[super init])) actual=candidate?[CandidateDelegate new]:[BaseDelegate new]; return self; }
- (NSUInteger)layoutManager:(NSLayoutManager *)manager shouldGenerateGlyphs:(const CGGlyph *)glyphs properties:(const NSGlyphProperty *)properties characterIndexes:(const NSUInteger *)indexes font:(NSFont *)font forGlyphRange:(NSRange)range {
    GlyphCalls++; Glyphs+=range.length;
    double start=Now();
    NSUInteger result=[actual layoutManager:manager shouldGenerateGlyphs:glyphs properties:properties characterIndexes:indexes font:font forGlyphRange:range];
    DelegateMs+=(Now()-start)*1000;
    if(result) Adjusted++;
    return result;
}
- (void)dealloc { [actual release]; [super dealloc]; }
@end
@interface System : NSObject {
@public NSTextStorage *storage; NSLayoutManager *layout; NSTextContainer *container; Observer *observer;
}
- (id)initSource:(NSString *)source candidate:(BOOL)candidate font:(NSString *)font;
- (NSDictionary *)shape;
@end
@implementation System
- (id)initSource:(NSString *)source candidate:(BOOL)candidate font:(NSString *)font {
    if ((self=[super init])) {
        storage=[NSTextStorage new]; layout=[NSLayoutManager new];
        container=[[NSTextContainer alloc] initWithSize:NSMakeSize(544,10000000)];
        observer=[[Observer alloc] initCandidate:candidate];
        [storage addLayoutManager:layout]; [layout addTextContainer:container];
        layout.delegate=observer; layout.typesetter=[[[NVSourceTypesetter alloc] init] autorelease];
        NSMutableParagraphStyle *style=[[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
        style.lineBreakMode=NSLineBreakByCharWrapping;
        NSFont *face=[NSFont fontWithName:font size:16]; Check(face!=nil,@"fixture font exists");
        [storage setAttributedString:[[[NSAttributedString alloc] initWithString:source attributes:@{NSFontAttributeName:face,NSParagraphStyleAttributeName:style}] autorelease]];
    }
    return self;
}
- (NSDictionary *)shape {
    __block NSUInteger lines=0, covered=0;
    __block uint64_t hash=1469598103934665603ULL;
    [layout enumerateLineFragmentsForGlyphRange:NSMakeRange(0,layout.numberOfGlyphs) usingBlock:^(NSRect rect,NSRect used,NSTextContainer *text,NSRange range,BOOL *stop) {
        Check(range.location==covered && isfinite(used.size.width) && isfinite(rect.origin.y),@"finite consecutive line fragments");
        covered=NSMaxRange(range); lines++;
        hash=(hash ^ range.location)*1099511628211ULL; hash=(hash ^ range.length)*1099511628211ULL;
    }];
    Check(covered==layout.numberOfGlyphs,@"complete glyph layout");
    uint64_t properties=1469598103934665603ULL;
    for(NSUInteger i=0;i<layout.numberOfGlyphs;i++) properties=(properties ^ [layout propertyForGlyphAtIndex:i])*1099511628211ULL;
    return @{@"lines":@(lines),@"glyphs":@(covered),@"line_hash":@(hash),@"property_hash":@(properties)};
}
- (void)dealloc { layout.delegate=nil; [observer release]; [container release]; [layout release]; [storage release]; [super dealloc]; }
@end
static NSMutableDictionary *Record(double elapsed) {
    Check(Mallocs==Frees,@"delegate buffers are released");
    return [NSMutableDictionary dictionaryWithDictionary:@{@"wall_ms":@(elapsed),@"delegate_ms":@(DelegateMs),@"glyph_callbacks":@(GlyphCalls),@"glyphs_visited":@(Glyphs),@"composed_queries":@(Composed),@"explicit_buffer_allocations":@(Mallocs),@"explicit_buffer_bytes":@(MallocBytes),@"adjusted_callbacks":@(Adjusted),@"typesetter_creates":@(Creates),@"snapshot_characters":@(SnapshotChars),@"cluster_suggestions":@(Suggests),@"line_creates":@(Lines),@"token_advances":@(Tokens)}];
}
static NSString *Repeat(NSString *pattern, NSUInteger target) {
    NSMutableString *text=[NSMutableString string];
    while(text.length<target) [text appendString:pattern];
    return text;
}
static NSArray *Fixtures(void) {
    NSString *prose=@"alpha beta gamma delta epsilon zeta eta theta iota kappa lambda omega ";
    NSString *marks=Repeat(@"\u0301",256);
    return @[
        @{@"name":@"short-note",@"text":Repeat(@"Meeting notes for Friday. Finish the draft and review the next steps.\n",384),@"font":@"Menlo-Regular"},
        @{@"name":@"short-proportional",@"text":Repeat(prose,384),@"font":@"Helvetica"},
        @{@"name":@"prose-4096",@"text":Repeat(prose,4096),@"font":@"Menlo-Regular"},
        @{@"name":@"prose-32768",@"text":Repeat(prose,32768),@"font":@"Menlo-Regular"},
        @{@"name":@"spaces-32768",@"text":Repeat(@" ",32768),@"font":@"Menlo-Regular"},
        @{@"name":@"indent-and-runs",@"text":Repeat(@"    alpha  beta    gamma delta\n",8192),@"font":@"Menlo-Regular"},
        @{@"name":@"composed-prose",@"text":Repeat(@"café e\u0302 👩🏽‍💻 中文 zeta eta theta \u0301word \ufe0fword \u200dword\n",8192),@"font":@"Menlo-Regular"},
        @{@"name":@"long-composed-spaces",@"text":Repeat([NSString stringWithFormat:@"a %@b c ",marks],8192),@"font":@"Menlo-Regular"}
    ];
}
int main(int argc, const char **argv) { @autoreleasepool {
    Check(argc==2,@"output path supplied");
    NSMutableArray *records=[NSMutableArray array];
#ifdef COUNTS
    NSUInteger trials=1;
#else
    NSUInteger trials=5;
#endif
    for(NSDictionary *fixture in Fixtures()) {
        NSString *source=fixture[@"text"];
        NSRange search=NSMakeRange(source.length/2,source.length-source.length/2);
        NSRange space=[source rangeOfString:@" " options:0 range:search];
        Check(space.location!=NSNotFound,@"fixture has editable space");
        NSUInteger insertion=space.location+1;
        for(NSUInteger trial=0;trial<trials;trial++) for(NSUInteger order=0;order<2;order++) { @autoreleasepool {
            BOOL candidate=(trial+order)%2;
            System *system=[[[System alloc] initSource:source candidate:candidate font:fixture[@"font"]] autorelease];
            Reset(); double start=Now(); [system->layout ensureLayoutForTextContainer:system->container];
            NSMutableDictionary *initial=Record((Now()-start)*1000);
            NSDictionary *shape=[system shape];
            Reset(); start=Now();
            [system->storage replaceCharactersInRange:NSMakeRange(insertion,0) withString:@" "];
            [system->layout ensureLayoutForTextContainer:system->container];
            [system->storage replaceCharactersInRange:NSMakeRange(insertion,1) withString:@""];
            [system->layout ensureLayoutForTextContainer:system->container];
            NSMutableDictionary *incremental=Record((Now()-start)*1000);
            Check([system->storage.string isEqual:source],@"incremental history preserves source");
            Check([[system shape] isEqual:shape],@"incremental restore matches initial line boundaries and glyph properties");
            Reset();
            for(int i=0;i<8;i++) [system->layout ensureLayoutForTextContainer:system->container];
            Check(GlyphCalls==0 && Creates==0 && Composed==0,@"cached layout performs no delegate or typesetter work");
            for(NSMutableDictionary *row in @[initial,incremental]) {
                [row addEntriesFromDictionary:@{@"fixture":fixture[@"name"],@"characters":@(source.length),@"font":fixture[@"font"],@"variant":candidate?@"candidate":@"base",@"trial":@(trial),@"operation":row==initial?@"initial":@"incremental",@"shape":shape}];
                [records addObject:row];
            }
        }}
        fprintf(stderr,"complete %s\n",[fixture[@"name"] UTF8String]);
    }
    Check(NSApp==nil,@"no application or GUI created");
    NSDictionary *report=@{@"records":records,@"checks":@(Checks),@"trials_per_variant":@(trials),@"incremental_edits_per_sample":@2,@"cached_queries_per_layout":@8,@"result":@"PASS"};
    Check([[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES],@"results written");
    fprintf(stderr,"PASS %lu checks\n",(unsigned long)Checks);
    return 0;
}}
