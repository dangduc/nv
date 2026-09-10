#import "NVNoteEditingSession.h"
#import "NoteObject.h"
#import "NVSourceHighlighter.h"
#import "AttributedPlainText.h"
#import "GlobalPrefs.h"

NSString * const NVNoteContentsDidChangeNotification = @"NVNoteContentsDidChange";
NSString * const NVNoteEditorDidChangeNotification = @"NVNoteEditorDidChange";

@interface NSObject (NVEditingConflictOwner)
- (void)preserveExternalContents:(NSAttributedString *)contents forNote:(NoteObject *)note;
@end

@interface NVNoteEditingSession (NVMetadataHistory)
- (void)restoreMetadataValue:(NSString *)value isTitle:(BOOL)isTitle;
@end

// A separate target lets external body snapshots discard text history without
// discarding metadata history. The session owns this target and clears its actions.
@interface NVNoteMetadataUndoTarget : NSObject {
    NVNoteEditingSession *session; // Borrowed from the owner.
}
- (id)initWithSession:(NVNoteEditingSession *)editingSession;
- (void)restoreMetadataValue:(NSString *)value isTitle:(BOOL)isTitle;
@end

@implementation NVNoteMetadataUndoTarget
- (id)initWithSession:(NVNoteEditingSession *)editingSession {
    if ((self = [super init])) session = editingSession;
    return self;
}
- (void)restoreMetadataValue:(NSString *)value isTitle:(BOOL)isTitle {
    [session restoreMetadataValue:value isTitle:isTitle];
}
@end

// A single replacement describes each side of an interrupted composition.
static NSRange NVChangedRange(NSString *before, NSString *after, NSRange *replacementRange) {
    NSUInteger prefix = 0, oldEnd = [before length], newEnd = [after length];
    while (prefix < oldEnd && prefix < newEnd && [before characterAtIndex:prefix] == [after characterAtIndex:prefix]) prefix++;
    while (oldEnd > prefix && newEnd > prefix && [before characterAtIndex:oldEnd - 1] == [after characterAtIndex:newEnd - 1]) { oldEnd--; newEnd--; }
    *replacementRange = NSMakeRange(prefix, newEnd - prefix);
    return NSMakeRange(prefix, oldEnd - prefix);
}

typedef struct { NSRange oldRange, newRange; } NVSnapshotEdit;
typedef struct { NSUInteger reachedPlusOne; BOOL insertion; } NVSnapshotStep;

// Bound both the edit distance and search work. Large or distant changes use
// the existing single-range replacement instead of an unbounded document diff.
static NSArray *NVSnapshotEdits(NSString *before, NSString *after, NSRange changed, NSRange replacement) {
    NSUInteger n = changed.length, m = replacement.length;
    NSUInteger limit = MIN(256U, n + m), work = 0;
    if (!n || !m || (n > m ? n - m : m - n) > limit) return nil;
    NSUInteger width = 2 * limit + 3, offset = limit + 1;
    NSMutableData *trace = [[NSMutableData alloc] initWithLength:(limit + 1) * width * sizeof(NVSnapshotStep)];
    NVSnapshotStep *steps = [trace mutableBytes];
    NSInteger distance = -1;
    for (NSUInteger d = 0; d <= limit && distance < 0; d++) {
        NVSnapshotStep *row = steps + d * width;
        NVSnapshotStep *previous = d ? row - width : NULL;
        for (NSInteger k = -(NSInteger)d; k <= (NSInteger)d; k += 2) {
            if (++work > 1000000U) { [trace release]; return nil; }
            NSInteger x = 0;
            BOOL insertion = NO;
            if (d) {
                NSInteger deleted = -1, inserted = -1;
                if (previous[offset + k - 1].reachedPlusOne) {
                    NSUInteger oldX = previous[offset + k - 1].reachedPlusOne - 1;
                    if (oldX < n) deleted = oldX + 1;
                }
                if (previous[offset + k + 1].reachedPlusOne) {
                    NSUInteger oldX = previous[offset + k + 1].reachedPlusOne - 1;
                    NSInteger oldY = (NSInteger)oldX - (k + 1);
                    if (oldY < (NSInteger)m) inserted = oldX;
                }
                if (deleted < 0 && inserted < 0) continue;
                // Prefer deletion on ties, so repeated-text matches are deterministic.
                insertion = inserted > deleted;
                x = insertion ? inserted : deleted;
            }
            NSInteger y = x - k;
            while (x < (NSInteger)n && y < (NSInteger)m) {
                if (++work > 1000000U) { [trace release]; return nil; }
                if ([before characterAtIndex:changed.location + x] != [after characterAtIndex:replacement.location + y]) break;
                x++; y++;
            }
            row[offset + k].reachedPlusOne = x + 1;
            row[offset + k].insertion = insertion;
            if (x == (NSInteger)n && y == (NSInteger)m) { distance = d; break; }
        }
    }
    if (distance < 0) { [trace release]; return nil; }
    NSMutableArray *edits = [NSMutableArray array];
    NSInteger x = n, y = m;
    for (NSInteger d = distance; d > 0; d--) {
        NSInteger k = x - y;
        BOOL insertion = steps[d * width + offset + k].insertion;
        NSInteger previousK = insertion ? k + 1 : k - 1;
        NSInteger previousX = steps[(d - 1) * width + offset + previousK].reachedPlusOne - 1;
        NSInteger previousY = previousX - previousK;
        while (x > previousX && y > previousY) { x--; y--; }
        NVSnapshotEdit edit;
        if (insertion) {
            y--;
            edit = (NVSnapshotEdit){NSMakeRange(changed.location + x, 0), NSMakeRange(replacement.location + y, 1)};
        } else {
            x--;
            edit = (NVSnapshotEdit){NSMakeRange(changed.location + x, 1), NSMakeRange(replacement.location + y, 0)};
        }
        // Coalesce adjacent operations into replacements. Unchanged interior
        // characters separate spans and retain their native Cocoa selections.
        if ([edits count]) {
            NVSnapshotEdit right;
            [[edits lastObject] getValue:&right];
            if (NSMaxRange(edit.oldRange) == right.oldRange.location && NSMaxRange(edit.newRange) == right.newRange.location) {
                edit.oldRange.length += right.oldRange.length;
                edit.newRange.length += right.newRange.length;
                [edits removeLastObject];
            }
        }
        [edits addObject:[NSValue valueWithBytes:&edit objCType:@encode(NVSnapshotEdit)]];
    }
    [trace release];
    return edits;
}

@implementation NVNoteEditingSession
- (id)initWithNote:(NoteObject *)aNote {
    if ((self = [super init])) {
        note = [aNote retain];
        [[note undoManager] setGroupsByEvent:NO];
        [[note undoManager] setLevelsOfUndo:200];
        metadataUndoTarget = [[NVNoteMetadataUndoTarget alloc] initWithSession:self];
        committedContents = [[note contentString] copy];
        textStorage = [[NSTextStorage alloc] initWithString:[committedContents string] attributes:[[GlobalPrefs defaultPrefs] noteBodyAttributes]];
        [textStorage addLinkAttributesForRange:NSMakeRange(0, [textStorage length]) syntaxIdentifier:[note sourceSyntaxIdentifier]];
        sourceGeneration = 1;
        sourceFont = [[[GlobalPrefs defaultPrefs] noteBodyFont] retain];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sourceCharactersChanged:) name:NSTextStorageDidProcessEditingNotification object:textStorage];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sourceSyntaxChanged:) name:NVNoteSyntaxDidChangeNotification object:note];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(noteContentsChanged:)
                                                     name:NVNoteContentsDidChangeNotification object:note];
    }
    return self;
}
- (NoteObject *)note { return note; }
- (NSTextStorage *)textStorage { return textStorage; }
- (uint64_t)sourceGeneration { return sourceGeneration; }
- (void)sourceCharactersChanged:(NSNotification *)notification {
    if ([textStorage editedMask] & NSTextStorageEditedCharacters) sourceGeneration++;
}
- (void)sourceSyntaxChanged:(NSNotification *)notification {
    NSRange range = NSMakeRange(0, [textStorage length]);
    [textStorage removeAttribute:NSLinkAttributeName range:range];
    [textStorage addLinkAttributesForRange:range syntaxIdentifier:[note sourceSyntaxIdentifier]];
    [sourceHighlighter setSyntaxIdentifier:[note sourceSyntaxIdentifier]];
}
- (void)sourceLayoutDidAttach {
    [self refreshSourceFont];
    if (!sourceHighlighter) sourceHighlighter = [[NVSourceHighlighter alloc] initWithTextStorage:textStorage syntaxIdentifier:[note sourceSyntaxIdentifier]];
    [sourceHighlighter layoutsChanged];
}
- (void)sourceLayoutDidDetach {
    if (![[textStorage layoutManagers] count]) {
        [sourceHighlighter close]; [sourceHighlighter release]; sourceHighlighter = nil;
    }
}

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
- (void)applyContents:(NSAttributedString *)contents {
    NSAttributedString *snapshot = [contents copy];
    NSRange replacement;
    NSRange changed = NVChangedRange([textStorage string], [snapshot string], &replacement);
    NSArray *edits = NVSnapshotEdits([textStorage string], [snapshot string], changed, replacement);
    if (edits) {
        // Apply from end to start, without batching character notifications:
        // Cocoa adjusts every selected range for each separate replacement.
        for (NSValue *value in edits) {
            NVSnapshotEdit edit;
            [value getValue:&edit];
            [textStorage replaceCharactersInRange:edit.oldRange withAttributedString:[snapshot attributedSubstringFromRange:edit.newRange]];
        }
    } else if (changed.length || replacement.length) {
        [textStorage replaceCharactersInRange:changed withAttributedString:[snapshot attributedSubstringFromRange:replacement]];
    }
    // Source snapshots retain characters. The current source font supplies the
    // Cocoa wrapper attributes, including after Undo to an older snapshot.
    [textStorage setAttributes:[[GlobalPrefs defaultPrefs] noteBodyAttributes] range:NSMakeRange(0, [textStorage length])];
    [sourceFont release]; sourceFont = [[[GlobalPrefs defaultPrefs] noteBodyFont] retain];
    [textStorage addLinkAttributesForRange:NSMakeRange(0, [textStorage length]) syntaxIdentifier:[note sourceSyntaxIdentifier]];
    [snapshot release];
}
- (void)refreshSourceFont {
    NSFont *font = [[GlobalPrefs defaultPrefs] noteBodyFont];
    if ([sourceFont isEqual:font] || [self hasMarkedText]) return;
    [textStorage addAttributes:[[GlobalPrefs defaultPrefs] noteBodyAttributes] range:NSMakeRange(0, [textStorage length])];
    [sourceFont release]; sourceFont = [font retain];
}
- (void)reloadFromNote {
    if (writingNote) return;
    if ([self hasMarkedText]) {
        [pendingExternalContents release];
        pendingExternalContents = [[[note contentString] string] isEqualToString:[committedContents string]] ? nil : [[note contentString] copy];
        return;
    }
    [pendingExternalContents release];
    pendingExternalContents = nil;
    if ([[[note contentString] string] isEqualToString:[committedContents string]]) { [self refreshSourceFont]; return; }
    [[note undoManager] removeAllActionsWithTarget:self];
    [self applyContents:[note contentString]];
    [committedContents release];
    committedContents = [[note contentString] copy];
    [self broadcastChange];
}
- (void)writeContentsToNote {
    [self refreshSourceFont];
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
    [self applyContents:contents];
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
- (void)setMetadataValue:(NSString *)value isTitle:(BOOL)isTitle {
    NSString *oldValue = isTitle ? titleOfNote(note) : labelsOfNote(note) ?: @"";
    if ([oldValue isEqualToString:value]) return;
    [self finishEditingForHistoryChange];
    [[note undoManager] beginUndoGrouping];
    [self restoreMetadataValue:value isTitle:isTitle];
    [[note undoManager] endUndoGrouping];
}
- (void)restoreMetadataValue:(NSString *)value isTitle:(BOOL)isTitle {
    if (![[[note delegate] allNotes] containsObject:note]) return;
    NSString *oldValue = [[(isTitle ? titleOfNote(note) : labelsOfNote(note) ?: @"") copy] autorelease];
    NSUndoManager *undo = [note undoManager];
    // Only the value is retained by history; retaining the note here would cycle
    // through the note's own undo manager.
    [[undo prepareWithInvocationTarget:metadataUndoTarget] restoreMetadataValue:oldValue isTitle:isTitle];
    if (isTitle) [note setTitleString:value];
    else [note setLabelString:value];
    [undo setActionName:isTitle ? NSLocalizedString(@"Rename Note", nil) : NSLocalizedString(@"Edit Tags", nil)];
}
- (void)commitPendingTextChanges {
    [self refreshSourceFont];
    // Layout and attachment can normalize attributes without a user edit.
    if (pendingExternalContents || [self hasPendingTextChanges]) [self commitTextChanges];
}
- (void)commitTextChanges {
    if (writingNote || [self hasMarkedText]) return;
    [self refreshSourceFont];
    if ([[textStorage string] isEqualToString:[committedContents string]]) {
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
        // Attribute-only changes have no replacement text and cannot conflict here.
        if (local.location == remote.location && !local.length && !remote.length && localReplacement.length && remoteReplacement.length) separate = NO;
        if (separate) {
            NSMutableAttributedString *merged = [pendingExternalContents mutableCopy];
            if (local.location >= NSMaxRange(remote)) local.location += (NSInteger)remoteReplacement.length - (NSInteger)remote.length;
            [merged replaceCharactersInRange:local withAttributedString:[textStorage attributedSubstringFromRange:localReplacement]];
            [self applyContents:merged];
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
    [self closeWithoutCommitting];
}
- (void)closeWithoutCommitting {
    [sourceHighlighter close]; [sourceHighlighter release]; sourceHighlighter = nil;
    [[note undoManager] removeAllActionsWithTarget:self];
    [[note undoManager] removeAllActionsWithTarget:metadataUndoTarget];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (void)dealloc {
    [sourceHighlighter close]; [sourceHighlighter release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[note undoManager] removeAllActionsWithTarget:self];
    [[note undoManager] removeAllActionsWithTarget:metadataUndoTarget];
    [metadataUndoTarget release];
    [sourceFont release];
    [note release];
    [textStorage release];
    [committedContents release];
    [pendingExternalContents release];
    [super dealloc];
}
@end
