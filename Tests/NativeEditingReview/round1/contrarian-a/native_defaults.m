#import <Cocoa/Cocoa.h>

int main(void) {
    @autoreleasepool {
        NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 320, 200)];
        printf("continuousSpellChecking=%d\n", [view isContinuousSpellCheckingEnabled]);
        printf("automaticSpellingCorrection=%d\n", [view isAutomaticSpellingCorrectionEnabled]);
        printf("automaticQuoteSubstitution=%d\n", [view isAutomaticQuoteSubstitutionEnabled]);
        printf("automaticDashSubstitution=%d\n", [view isAutomaticDashSubstitutionEnabled]);
        printf("automaticTextReplacement=%d\n", [view isAutomaticTextReplacementEnabled]);
        printf("smartInsertDelete=%d\n", [view smartInsertDeleteEnabled]);
        [view release];
    }
    return 0;
}
