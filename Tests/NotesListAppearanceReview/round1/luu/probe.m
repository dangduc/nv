#import <Cocoa/Cocoa.h>
#import <time.h>
#import "NSBezierPath_NV.h"

static float fontSize = 15;
@interface GlobalPrefs : NSObject
+ (id)defaultPrefs;
- (float)tableFontSize;
@end
@implementation GlobalPrefs
+ (id)defaultPrefs { static GlobalPrefs *prefs; if (!prefs) prefs = [[self alloc] init]; return prefs; }
- (float)tableFontSize { return fontSize; }
@end

@interface CurrentCache : NSObject { NSMutableDictionary *labelImages; }
- (NSImage *)cachedLabelImageForWord:(NSString *)word highlighted:(BOOL)selected;
- (void)invalidateCachedLabelImages;
- (NSUInteger)cacheCount;
@end
@implementation CurrentCache
#include "current.inc"
#include "invalidate.inc"
- (NSUInteger)cacheCount { return [labelImages count]; }
- (void)dealloc { [labelImages release]; [super dealloc]; }
@end

@interface BaselineCache : NSObject { NSMutableDictionary *labelImages; }
- (NSImage *)cachedLabelImageForWord:(NSString *)word highlighted:(BOOL)selected;
@end
@implementation BaselineCache
#include "baseline.inc"
- (void)dealloc { [labelImages release]; [super dealloc]; }
@end

static unsigned assertions;
static void Check(BOOL value, const char *message) {
    if (!value) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
    assertions++;
}
static double Now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}
static double TimedHits(id cache, NSArray *words, NSAppearance *appearance, NSUInteger calls) {
    __block double elapsed = 0;
    [appearance performAsCurrentDrawingAppearance:^{
        double start = Now();
        for (NSUInteger batch=0; batch<calls/1000; batch++) {
            @autoreleasepool {
                for (NSUInteger i=0; i<1000; i++) {
                    // Use fixed words and selection states for both implementations.
                    [cache cachedLabelImageForWord:[words objectAtIndex:i%[words count]] highlighted:(i/32)%2];
                }
            }
        }
        elapsed = (Now() - start) * 1000;
    }];
    return elapsed;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSArray *appearanceNames = @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua,
            NSAppearanceNameAccessibilityHighContrastAqua, NSAppearanceNameAccessibilityHighContrastDarkAqua];
        NSMutableArray *appearances = [NSMutableArray array];
        for (NSString *name in appearanceNames) {
            NSAppearance *appearance = [NSAppearance appearanceNamed:name];
            Check(appearance != nil, "fixture appearance exists");
            [appearances addObject:appearance];
        }
        NSMutableArray *words = [NSMutableArray array];
        for (NSUInteger i=0; i<32; i++) [words addObject:[NSString stringWithFormat:@"project-%02lu", (unsigned long)i]];
        CurrentCache *current = [[[CurrentCache alloc] init] autorelease];
        NSMutableDictionary *firstImages = [NSMutableDictionary dictionary];
        for (NSUInteger a=0; a<[appearances count]; a++) {
            [[appearances objectAtIndex:a] performAsCurrentDrawingAppearance:^{
                for (NSUInteger w=0; w<[words count]; w++) for (NSUInteger h=0; h<2; h++) {
                    NSString *key = [NSString stringWithFormat:@"%lu/%lu/%lu", a,w,h];
                    NSImage *image = [current cachedLabelImageForWord:words[w] highlighted:h];
                    Check(image != nil, "initial raster exists");
                    firstImages[key] = image;
                }
            }];
        }
        NSUInteger warmedEntries = [current cacheCount];
        Check(warmedEntries <= 32*2*4, "cache does not exceed word/state/appearance combinations");
        Check(firstImages[@"0/0/0"] != firstImages[@"1/0/0"], "light and dark normal tags use different raster images");
        for (NSUInteger cycle=0; cycle<80; cycle++) {
            @autoreleasepool {
                for (NSUInteger a=0; a<[appearances count]; a++) {
                    [[appearances objectAtIndex:a] performAsCurrentDrawingAppearance:^{
                        for (NSUInteger w=0; w<[words count]; w++) for (NSUInteger h=0; h<2; h++) {
                            NSString *key = [NSString stringWithFormat:@"%lu/%lu/%lu",a,w,h];
                            Check([current cachedLabelImageForWord:words[w] highlighted:h] == firstImages[key],
                                  "repeated appearance draw reuses the original raster");
                        }
                    }];
                }
                Check([current cacheCount] == warmedEntries, "appearance cycles do not grow the warmed cache");
            }
        }
        [firstImages removeAllObjects];
        // The production font-change callback calls this exact invalidation method.
        for (NSUInteger change=0; change<8; change++) {
            fontSize = (float[]){12,15,19,31}[change%4];
            [current invalidateCachedLabelImages];
            Check([current cacheCount] == 0, "font invalidation releases all cached dictionary entries");
            for (NSAppearance *appearance in appearances) {
                [appearance performAsCurrentDrawingAppearance:^{
                    for (NSString *word in words) for (NSUInteger h=0;h<2;h++) {
                        NSImage *image = [current cachedLabelImageForWord:word highlighted:h];
                        Check([image size].height == roundf((fontSize-1)*1.3), "new raster height uses the current font");
                    }
                }];
            }
            Check([current cacheCount] == warmedEntries, "font changes replace old variants without adding generations");
        }
        fontSize = 15;
        [current invalidateCachedLabelImages];
        BaselineCache *baseline = [[[BaselineCache alloc] init] autorelease];
        for (NSAppearance *appearance in appearances) {
            [appearance performAsCurrentDrawingAppearance:^{
                for (NSString *word in words) for (NSUInteger h=0;h<2;h++) {
                    [current cachedLabelImageForWord:word highlighted:h];
                    [baseline cachedLabelImageForWord:word highlighted:h];
                }
            }];
        }
        NSMutableArray *currentMS = [NSMutableArray array], *baselineMS = [NSMutableArray array];
        const NSUInteger calls = 100000;
        // Alternate pair order. Each sample contains the same two appearance batches.
        for (NSUInteger sample=0;sample<7;sample++) {
            double c=0,b=0;
            for (NSUInteger a=0;a<2;a++) {
                NSAppearance *appearance = appearances[a];
                if (sample%2) { c+=TimedHits(current,words,appearance,calls); b+=TimedHits(baseline,words,appearance,calls); }
                else { b+=TimedHits(baseline,words,appearance,calls); c+=TimedHits(current,words,appearance,calls); }
            }
            [currentMS addObject:@(c)]; [baselineMS addObject:@(b)];
            Check([current cacheCount] == warmedEntries, "timed warm calls add no cached raster images");
        }
        NSDictionary *report = @{ @"assertions": @(assertions), @"warm_cache_entries": @(warmedEntries),
            @"appearance_cycles": @80, @"words": @32, @"font_changes": @8,
            @"calls_per_paired_sample": @(calls*2), @"current_ms":currentMS, @"baseline_ms":baselineMS };
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingSortedKeys error:NULL];
        printf("PASS: %u cache identity, cardinality, and font checks\n%s\n", assertions,
               [[[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] autorelease] UTF8String]);
    }
    return 0;
}
