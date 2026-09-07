#import "NVNoteEditingSession.h"
#import "NoteObject.h"

NSString * const NVNoteContentsDidChangeNotification = @"NVNoteContentsDidChange";
NSString * const NVNoteEditorDidChangeNotification = @"NVNoteEditorDidChange";

@interface NSObject (NVEditingConflictOwner)
- (void)preserveExternalContents:(NSAttributedString *)contents forNote:(NoteObject *)note;
@end

// A single replacement describes each side of an interrupted composition.
static NSRange NVChangedRange(NSString *before, NSString *after, NSRange *replacementRange) {
    NSUInteger prefix = 0, oldEnd = [before length], newEnd = [after length];
    while (prefix < oldEnd && prefix < newEnd && [before characterAtIndex:prefix] == [after characterAtIndex:prefix]) prefix++;
    while (oldEnd > prefix && newEnd > prefix && [before characterAtIndex:oldEnd - 1] == [after characterAtIndex:newEnd - 1]) { oldEnd--; newEnd--; }
    *replacementRange = NSMakeRange(prefix, newEnd - prefix);
    return NSMakeRange(prefix, oldEnd - prefix);
}

@implementation NVNoteEditingSession
- (id)initWithNote:(NoteObject *)aNote {
    if ((self = [super init])) {
        note = [aNote retain];
        [[note undoManager] setGroupsByEvent:NO];
        [[note undoManager] setLevelsOfUndo:200];
        committedContents = [[note contentString] copy];
        textStorage = [[NSTextStorage alloc] initWithAttributedString:committedContents];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(noteContentsChanged:)
                                                     name:NVNoteContentsDidChangeNotification object:note];
    }
    return self;
}
- (NoteObject *)note { return note; }
- (NSTextStorage *)textStorage { return textStorage; }
- (BOOL)hasMarkedText {
    for (NSLayoutManager *layout in [textStorage layoutManagers]) {
        for (NSTextContainer *container in [layout textContainers]) {
            if ([[container textView] hasMarkedText]) return YES;
        }
    }
    return NO;
}
- (void)noteContentsChanged:(NSNotification *)notification { if (!writingNote) [self reloadFromNote]; }
- (void)broadcastChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:NVNoteEditorDidChangeNotification object:note];
}
- (void)reloadFromNote {
    if (writingNote) return;
    if ([self hasMarkedText]) {
        [pendingExternalContents release];
        pendingExternalContents = [[note contentString] copy];
        return;
    }
    [pendingExternalContents release];
    pendingExternalContents = nil;
    if ([[note contentString] isEqualToAttributedString:committedContents]) return;
    [[note undoManager] removeAllActionsWithTarget:self];
    [textStorage setAttributedString:[note contentString]];
    [committedContents release];
    committedContents = [[note contentString] copy];
    [self broadcastChange];
}
- (void)writeContentsToNote {
    writingNote = YES;
    [note setContentString:textStorage];
    // Searches in other windows must see the current text immediately.
    [note updateContentCacheCStringIfNecessary];
    writingNote = NO;
    [committedContents release];
    committedContents = [textStorage copy];
    [self broadcastChange];
}
- (void)restoreContents:(NSAttributedString *)contents {
    NSAttributedString *previous = [[textStorage copy] autorelease];
    [[note undoManager] registerUndoWithTarget:self selector:@selector(restoreContents:) object:previous];
    [textStorage setAttributedString:contents];
    [self writeContentsToNote];
}
- (void)finishEditingForHistoryChange {
    // Any browser can invoke history while another attached editor is composing.
    for (NSLayoutManager *layout in [[[textStorage layoutManagers] copy] autorelease]) {
        for (NSTextContainer *container in [[[layout textContainers] copy] autorelease]) {
            NSTextView *view = [container textView];
            if ([view hasMarkedText]) [view unmarkText];
        }
    }
    [self commitPendingTextChanges];
}
- (BOOL)hasPendingTextChanges {
    return ![[textStorage string] isEqualToString:[committedContents string]];
}
- (BOOL)canUndo {
    return [self hasPendingTextChanges] || (!pendingExternalContents && [[note undoManager] canUndo]);
}
- (BOOL)canRedo {
    return !pendingExternalContents && ![self hasPendingTextChanges] && [[note undoManager] canRedo];
}
- (void)undo {
    [self finishEditingForHistoryChange];
    if ([[note undoManager] canUndo]) [[note undoManager] undo];
}
- (void)redo {
    [self finishEditingForHistoryChange];
    if ([[note undoManager] canRedo]) [[note undoManager] redo];
}
- (void)commitPendingTextChanges {
    // Layout and attachment can normalize attributes without a user edit.
    if (pendingExternalContents || [self hasPendingTextChanges]) [self commitTextChanges];
}
- (void)commitTextChanges {
    if (writingNote || [self hasMarkedText]) return;
    if ([textStorage isEqualToAttributedString:committedContents]) {
        if (pendingExternalContents) [self reloadFromNote];
        return;
    }
    NSAttributedString *undoContents = [[committedContents copy] autorelease];
    if (pendingExternalContents) {
        // Older snapshots predate this external update and cannot undo it safely.
        [[note undoManager] removeAllActionsWithTarget:self];
        NSRange localReplacement, remoteReplacement;
        NSRange local = NVChangedRange([committedContents string], [textStorage string], &localReplacement);
        NSRange remote = NVChangedRange([committedContents string], [pendingExternalContents string], &remoteReplacement);
        BOOL separate = NSMaxRange(local) <= remote.location || local.location >= NSMaxRange(remote);
        // Two insertions at the same position require an explicit preserved copy.
        if (local.location == remote.location && !local.length && !remote.length) separate = NO;
        if (separate) {
            NSMutableAttributedString *merged = [pendingExternalContents mutableCopy];
            if (local.location >= NSMaxRange(remote)) local.location += (NSInteger)remoteReplacement.length - (NSInteger)remote.length;
            [merged replaceCharactersInRange:local withAttributedString:[textStorage attributedSubstringFromRange:localReplacement]];
            [textStorage setAttributedString:merged];
            [merged release];
            undoContents = [[pendingExternalContents copy] autorelease];
        } else {
            id owner = [[note delegate] delegate];
            [owner preserveExternalContents:pendingExternalContents forNote:note];
        }
        [pendingExternalContents release];
        pendingExternalContents = nil;
    }
    [[note undoManager] beginUndoGrouping];
    [[note undoManager] registerUndoWithTarget:self selector:@selector(restoreContents:) object:undoContents];
    [[note undoManager] setActionName:NSLocalizedString(@"Edit Note", nil)];
    [[note undoManager] endUndoGrouping];
    [self writeContentsToNote];
}
- (void)close {
    [self commitPendingTextChanges];
    [[note undoManager] removeAllActionsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [note release];
    [textStorage release];
    [committedContents release];
    [pendingExternalContents release];
    [super dealloc];
}
@end
