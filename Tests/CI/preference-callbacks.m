#import "GlobalPrefs.h"
#include <assert.h>
#include <stdio.h>

static unsigned calls;
static id expectedReceiver, expectedSender;
static SEL expectedSelector;

@implementation GlobalPrefs
#include "dispatch.inc"
- (id)init {
    if ((self = [super init])) {
#include "assignment.inc"
    }
    return self;
}
- (void)notifyCallbacksForSelector:(SEL)selector excludingSender:(id)sender {
    assert(self == expectedReceiver);
    assert(_cmd == @selector(notifyCallbacksForSelector:excludingSender:));
    assert(selector == expectedSelector);
    assert(sender == expectedSender);
    calls++;
}
@end

int main(void) {
    @autoreleasepool {
        GlobalPrefs *prefs = [[GlobalPrefs alloc] init];
        NSObject *sender = [[NSObject alloc] init];
        expectedReceiver = prefs;
        expectedSender = sender;
        expectedSelector = @selector(unregisterTarget:);
        sendCallbacksForGlobalPrefs(prefs, expectedSelector, sender);
        assert(calls == 1);
        sendCallbacksForGlobalPrefs(prefs, expectedSelector, prefs);
        assert(calls == 1);
        [sender release];
        [prefs release];
    }
    puts("PASS: cached preference callback preserves receiver, selectors, sender and self-exclusion");
    return 0;
}
