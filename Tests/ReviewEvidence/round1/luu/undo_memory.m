#import <Cocoa/Cocoa.h>
#import <mach/mach.h>
#import "NVNoteEditingSession.h"

// Exercise production session code without files, editors, or the application.
@interface ProbeNote : NSObject {
    NSMutableAttributedString *contents;
    NSUndoManager *manager;
}
- (id)initWithLength:(NSUInteger)length;
- (NSMutableAttributedString *)contentString;
- (NSUndoManager *)undoManager;
- (void)setContentString:(NSAttributedString *)string;
- (void)updateContentCacheCStringIfNecessary;
@end
@implementation ProbeNote
- (id)initWithLength:(NSUInteger)length {
    if ((self = [super init])) {
        NSString *body = [@"x" stringByPaddingToLength:length withString:@"x" startingAtIndex:0];
        contents = [[NSMutableAttributedString alloc] initWithString:body];
        manager = [[NSUndoManager alloc] init];
    }
    return self;
}
- (NSMutableAttributedString *)contentString { return contents; }
- (NSUndoManager *)undoManager { return manager; }
- (void)setContentString:(NSAttributedString *)string {
    [contents setAttributedString:string];
    [[NSNotificationCenter defaultCenter] postNotificationName:NVNoteContentsDidChangeNotification object:self];
}
- (void)updateContentCacheCStringIfNecessary { }
- (void)dealloc { [contents release]; [manager release]; [super dealloc]; }
@end

static uint64_t footprint(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t result = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count);
    if (result != KERN_SUCCESS) abort();
    return info.phys_footprint;
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSUInteger length = argc > 1 ? strtoul(argv[1], NULL, 10) : 1048576;
        NSUInteger edits = argc > 2 ? strtoul(argv[2], NULL, 10) : 200;
        ProbeNote *note = [[ProbeNote alloc] initWithLength:length];
        NVNoteEditingSession *session = [[NVNoteEditingSession alloc] initWithNote:(id)note];
        uint64_t initial = footprint();
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        for (NSUInteger i = 0; i < edits; i++) {
            @autoreleasepool {
                [[session textStorage] replaceCharactersInRange:NSMakeRange(length + i, 0) withString:@"y"];
                [session commitTextChanges];
            }
        }
        uint64_t after = footprint();
        printf("length=%lu edits=%lu elapsed_ms=%.3f initial_mib=%.3f after_mib=%.3f delta_mib=%.3f\n",
            (unsigned long)length, (unsigned long)edits, (CFAbsoluteTimeGetCurrent() - start) * 1000,
            initial / 1048576.0, after / 1048576.0, (after - initial) / 1048576.0);
        NSUInteger count = 0;
        while ([[note undoManager] canUndo]) { [[note undoManager] undo]; count++; }
        printf("undo_count=%lu restored_initial=%s\n", (unsigned long)count,
            [[[note contentString] string] length] == length ? "yes" : "no");
        [session close];
        [session release]; [note release];
    }
    return 0;
}
