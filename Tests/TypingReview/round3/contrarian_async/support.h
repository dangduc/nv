#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "AppController.h"
#import "NVSourceAnalysis.h"
#import "AttributedPlainText.h"
#import "LinkingEditor.h"
#import "GlobalPrefs.h"
static NSLock *ObservationLock;
static NSMutableArray *Observations;
static NSMutableSet *LiveStoragePointers;
static NSString *ObservationPhase;
static IMP OriginalWords, OriginalLinks, OriginalSyntaxLinks;
static BOOL Await(BOOL (^condition)(void), NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    return condition();
}
static void Observe(id receiver, NSString *selector) {
    [ObservationLock lock];
    if (ObservationPhase) {
        NSString *queue = [NSString stringWithUTF8String:dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL)];
        BOOL live = [LiveStoragePointers containsObject:[NSValue valueWithPointer:receiver]];
        BOOL word = [selector isEqual:@"words"];
        uintptr_t begin = word ? (uintptr_t)&NVSourceWordCount : (uintptr_t)&NVSourceLinkRuns;
        NSUInteger size = strtoul(getenv(word ? "NV_WORD_HELPER_SIZE" : "NV_LINK_HELPER_SIZE"),NULL,10);
        uintptr_t workerBegin = (uintptr_t)&NVSourceWordCount + strtol(getenv("NV_WORKER_OFFSET"),NULL,10);
        NSUInteger workerSize = strtoul(getenv("NV_WORKER_SIZE"),NULL,10);
        BOOL worker = NO;
        BOOL helper = NO; NSMutableArray *offsets = [NSMutableArray array];
        for (NSNumber *address in [NSThread callStackReturnAddresses]) {
            uintptr_t pc = [address unsignedLongLongValue];
            if (pc>=workerBegin && pc<workerBegin+workerSize) worker=YES;
            if (pc>=begin && pc<begin+size) { helper=YES; [offsets addObject:@(pc-begin)]; }
        }
        [Observations addObject:@{@"phase":ObservationPhase, @"selector":selector,
            @"main":@([NSThread isMainThread]), @"live_storage":@(live),
            @"receiver":[NSString stringWithFormat:@"%p", receiver],
            @"class":NSStringFromClass([receiver class]), @"length":@([receiver length]),
            @"queue":queue, @"helper_frame":@(helper), @"worker_frame":@(worker), @"helper_offsets":offsets, @"helper_size":@(size), @"stack":[NSThread callStackSymbols]}];
    }
    [ObservationLock unlock];
}
static id ObservedWords(id object, SEL selector) {
    Observe(object, @"words"); return ((id (*)(id,SEL))OriginalWords)(object,selector);
}
static void ObservedLinks(id object, SEL selector, NSRange range) {
    Observe(object,@"addLinkAttributesForRange:"); ((void (*)(id,SEL,NSRange))OriginalLinks)(object,selector,range);
}
static void ObservedSyntaxLinks(id object, SEL selector, NSRange range, NSString *syntax) {
    Observe(object,@"addLinkAttributesForRange:syntaxIdentifier:"); ((void (*)(id,SEL,NSRange,id))OriginalSyntaxLinks)(object,selector,range,syntax);
}
static void InstallObservers(void) {
    ObservationLock = [NSLock new]; Observations = [NSMutableArray new]; LiveStoragePointers = [NSMutableSet new];
    OriginalWords = method_setImplementation(class_getInstanceMethod([NSTextStorage class], @selector(words)), (IMP)ObservedWords);
    OriginalLinks = method_setImplementation(class_getInstanceMethod([NSMutableAttributedString class], @selector(addLinkAttributesForRange:)), (IMP)ObservedLinks);
    OriginalSyntaxLinks = method_setImplementation(class_getInstanceMethod([NSMutableAttributedString class], @selector(addLinkAttributesForRange:syntaxIdentifier:)), (IMP)ObservedSyntaxLinks);
}
static NSUInteger OracleCount(NSString *source) {
    __block NSUInteger count = 0;
    dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
        @autoreleasepool { NSTextStorage *private = [[NSTextStorage alloc] initWithString:source]; count = [[private words] count]; [private release]; }
    }); return count;
}
static id LinkAt(LinkingEditor *editor, NSString *needle) {
    NSRange range = [editor.string rangeOfString:needle];
    return range.location == NSNotFound ? nil : [editor.textStorage attribute:NSLinkAttributeName atIndex:range.location effectiveRange:NULL];
}
