#import <Foundation/Foundation.h>
static NSUInteger CurrentTraceBytes, PeakTraceBytes, CharacterReads, Checks, Fallbacks;
// Count the allocation requested by the unchanged production helper.
@interface TraceData : NSObject { NSMutableData *data; }
- (id)initWithLength:(NSUInteger)length;
- (void *)mutableBytes;
@end
@implementation TraceData
- (id)initWithLength:(NSUInteger)length {
    if ((self = [super init])) {
        data = [[NSMutableData alloc] initWithLength:length];
        CurrentTraceBytes += length; PeakTraceBytes = MAX(PeakTraceBytes, CurrentTraceBytes);
    }
    return self;
}
- (void *)mutableBytes { return [data mutableBytes]; }
- (void)dealloc { CurrentTraceBytes -= [data length]; [data release]; [super dealloc]; }
@end
@interface CountedString : NSString { NSString *contents; }
- (id)initWithString:(NSString *)string;
@end
@implementation CountedString
- (id)initWithString:(NSString *)string { if ((self = [super init])) contents = [string copy]; return self; }
- (NSUInteger)length { return [contents length]; }
- (unichar)characterAtIndex:(NSUInteger)index { CharacterReads++; return [contents characterAtIndex:index]; }
- (void)getCharacters:(unichar *)buffer range:(NSRange)range { [contents getCharacters:buffer range:range]; }
- (void)dealloc { [contents release]; [super dealloc]; }
@end
#define NSMutableData TraceData
#include "snapshot-helper.inc"
#undef NSMutableData

static void Fail(NSString *message, NSString *before, NSString *after) {
    NSLog(@"FAIL: %@ before=%@ after=%@", message, before, after); exit(1);
}
static void Verify(NSString *before, NSString *after, BOOL mustFallback, BOOL countBounds) {
    @autoreleasepool {
        NSRange replacement;
        NSRange changed = NVChangedRange(before, after, &replacement);
        CountedString *old = [[[CountedString alloc] initWithString:before] autorelease];
        CountedString *next = [[[CountedString alloc] initWithString:after] autorelease];
        CharacterReads = 0;
        NSArray *edits = NVSnapshotEdits(old, next, changed, replacement);
        if (mustFallback && edits) Fail(@"expected bounded fallback", before, after);
        if (changed.length && replacement.length && changed.length + replacement.length <= 32 && !edits)
            Fail(@"small nonempty changes must produce hunks", before, after);
        if (CharacterReads > 2000000U) Fail(@"helper exceeds two character reads per allowed work step", before, after);
        if (CurrentTraceBytes) Fail(@"helper retains its temporary trace buffer", before, after);
        NSMutableString *applied = [[before mutableCopy] autorelease];
        NSUInteger previousLocation = NSUIntegerMax;
        if (edits) {
            for (NSValue *value in edits) {
                NVSnapshotEdit edit; [value getValue:&edit];
                if (edit.oldRange.location > [applied length] || edit.oldRange.length > [applied length] - edit.oldRange.location ||
                    edit.newRange.location > [after length] || edit.newRange.length > [after length] - edit.newRange.location)
                    Fail(@"hunk outside source or target bounds", before, after);
                if (NSMaxRange(edit.oldRange) > previousLocation) Fail(@"hunks overlap or are not in reverse order", before, after);
                previousLocation = edit.oldRange.location;
                [applied replaceCharactersInRange:edit.oldRange withString:[after substringWithRange:edit.newRange]];
            }
        } else {
            Fallbacks++;
            [applied replaceCharactersInRange:changed withString:[after substringWithRange:replacement]];
        }
        if ([applied length] != [after length]) Fail(@"applying hunks changes target UTF-16 length", before, after);
        for (NSUInteger i = 0; i < [after length]; i++) {
            if ([applied characterAtIndex:i] != [after characterAtIndex:i])
                Fail(@"applying hunks does not reproduce target UTF-16 units", before, after);
        }
        if (countBounds) printf("BOUNDED INPUT: before=%lu after=%lu fallback=%s character_reads=%lu peak_trace_bytes=%lu\n",
            (unsigned long)[before length], (unsigned long)[after length], edits ? "no" : "yes",
            (unsigned long)CharacterReads, (unsigned long)PeakTraceBytes);
        Checks++;
    }
}
static uint32_t Seed = 0x534E4150;
static uint32_t Next(void) { Seed = Seed * 1664525U + 1013904223U; return Seed; }
static NSString *RandomString(void) {
    unichar symbols[] = { 'a', 'b', 0x00e9, 0x0301, 0x4e2d, 0xd83d, 0xde42, 0x03a3, 0, '\n' };
    NSUInteger length = (Next() >> 8) % 81;
    unichar chars[81];
    for (NSUInteger i = 0; i < length; i++) chars[i] = symbols[(Next() >> 8) % 10];
    return [NSString stringWithCharacters:chars length:length];
}
int main(void) {
    @autoreleasepool {
        NSMutableArray *small = [NSMutableArray arrayWithObject:@""];
        for (NSUInteger length = 1; length <= 6; length++) for (NSUInteger value = 0; value < (1U << length); value++) {
            unichar chars[6];
            for (NSUInteger i = 0; i < length; i++) chars[i] = (value & (1U << i)) ? 'a' : 'b';
            [small addObject:[NSString stringWithCharacters:chars length:length]];
        }
        for (NSString *before in small) for (NSString *after in small) Verify(before, after, NO, NO);
        printf("EXHAUSTIVE: alphabet=ab max_length=6 pairs=%lu\n", (unsigned long)([small count] * [small count]));
        for (NSUInteger i = 0; i < 20000; i++) @autoreleasepool { Verify(RandomString(), RandomString(), NO, NO); }
        printf("RANDOM UTF16: seed=0x534E4150 pairs=20000 max_length=80 including_combining_nul_and_surrogate_units\n");
        for (NSArray *pair in @[@[@"🙂 middle 🙂", @"🙃 middle 🙃"], @[@"café", @"cafe\u0301"],
            @[@"Tiếng Việt", @"VIỆT tiếng"], @[@"prefix A stable B suffix", @"prefix C stable D suffix"]]) {
            Verify(pair[0], pair[1], NO, NO);
        }
        NSString *a4096 = [@"a" stringByPaddingToLength:4096 withString:@"a" startingAtIndex:0];
        NSString *b4096 = [@"b" stringByPaddingToLength:4096 withString:@"b" startingAtIndex:0];
        Verify(a4096, b4096, YES, YES); // Edit distance exceeds the frontier bound.
        Verify(@"a", b4096, YES, YES); // Length imbalance exits before trace allocation.
        NSString *interior = [@"a" stringByPaddingToLength:1000001 withString:@"a" startingAtIndex:0];
        Verify([@"x" stringByAppendingFormat:@"%@y", interior], [@"z" stringByAppendingFormat:@"%@w", interior], YES, YES);
        NSUInteger maximumTrace = 257U * 515U * sizeof(NVSnapshotStep);
        if (PeakTraceBytes > maximumTrace) { fprintf(stderr, "FAIL: trace exceeded bounded allocation\n"); return 1; }
        printf("SNAPSHOT DIFF PASSED: checks=%lu fallbacks=%lu max_trace_bytes=%lu\n",
            (unsigned long)Checks, (unsigned long)Fallbacks, (unsigned long)PeakTraceBytes);
    }
    return 0;
}
