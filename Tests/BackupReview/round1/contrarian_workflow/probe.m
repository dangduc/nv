#define main ExistingPreferenceSuiteMain
#include "../../../BackupPreferences/preferences.m"
#undef main

static NSUInteger beginEdits, endEdits;
static NSInteger retentionSeenByManualAction;

@interface WorkflowPane : NVBackupPreferencesViewController @end
@implementation WorkflowPane
- (void)controlTextDidBeginEditing:(NSNotification *)notification {
    beginEdits++;
    [super controlTextDidBeginEditing:notification];
}
- (void)controlTextDidEndEditing:(NSNotification *)notification {
    endEdits++;
    [super controlTextDidEndEditing:notification];
}
@end

@interface WorkflowController : NVBackupController @end
@implementation WorkflowController
- (void)backupNow:(id)sender {
    retentionSeenByManualAction = [[[self settings] objectForKey:@"recent"] integerValue];
    // The production coordinator captures retention, sets busy, and notifies observers in this order.
    // This fake does not serialize notes or touch a backup destination.
    [self setValue:@YES forKey:@"busy"];
    [[NSNotificationCenter defaultCenter] postNotificationName:NVBackupStatusDidChangeNotification object:self];
}
@end

static void Exercise(BOOL manual, BOOL expectFixed) {
    beginEdits = endEdits = 0;
    fakeBackup = [WorkflowController new];
    WorkflowPane *pane = [WorkflowPane new];
    NSView *view = [pane view];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:[view bounds]
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO];
    [window setContentView:view];
    NSTextField *recent = [pane valueForKey:@"recentField"];
    [recent selectText:nil];
    NSTextView *editor = (NSTextView *)[recent currentEditor];
    Check(editor != nil, @"Native field editor attached");
    [editor insertText:@"7" replacementRange:NSMakeRange(0, [[editor string] length])];
    Check(beginEdits == 1 && endEdits == 0, @"Native editing began without manually invoking delegates");
    Check([[recent stringValue] isEqualToString:@"7"] && [[[fakeBackup settings] objectForKey:@"recent"] integerValue] == 96,
        @"User has typed new retention but has not ended editing");

    if (manual) [[pane valueForKey:@"backupNowButton"] performClick:nil];
    else {
        [fakeBackup setValue:@YES forKey:@"busy"];
        [[NSNotificationCenter defaultCenter] postNotificationName:NVBackupStatusDidChangeNotification object:fakeBackup];
    }
    BOOL editorStillAttached = [recent currentEditor] != nil;
    [fakeBackup setValue:@NO forKey:@"busy"];
    [[NSNotificationCenter defaultCenter] postNotificationName:NVBackupStatusDidChangeNotification object:fakeBackup];
    NSString *after = [[recent stringValue] copy];
    [window makeFirstResponder:nil];
    NSInteger saved = [[[fakeBackup settings] objectForKey:@"recent"] integerValue];
    if (expectFixed) {
        Check(saved == 7, @"Busy transition preserves and eventually commits the user's retention edit");
        if (manual) Check(retentionSeenByManualAction == 7, @"Manual action uses the newly entered retention policy");
    } else {
        Check(!editorStillAttached && endEdits == 0, @"Busy disable detaches editor without end-edit notification");
        Check([after isEqualToString:@"96"] && saved == 96, @"Completion overwrites the unsaved retention edit");
        if (manual) Check(retentionSeenByManualAction == 96, @"Manual action captured the previous retention policy");
    }
    NSLog(@"%@: %@; typed=7, completion field=%@, saved=%ld, end-edit callbacks=%lu%@",
        expectFixed ? @"FIXED" : @"REPRODUCED", manual ? @"manual button" : @"automatic busy transition",
        after, (long)saved, (unsigned long)endEdits,
        manual ? [NSString stringWithFormat:@", action retention=%ld", (long)retentionSeenByManualAction] : @"");
    [after release];
    [window setContentView:nil];
    [window close]; [window release]; [pane release]; [fakeBackup release]; fakeBackup = nil;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [ProbeApplication sharedApplication];
        BOOL expectFixed = argc == 2 && strcmp(argv[1], "--expect-fixed") == 0;
        Exercise(NO, expectFixed);
        Exercise(YES, expectFixed);
    }
    return 0;
}
