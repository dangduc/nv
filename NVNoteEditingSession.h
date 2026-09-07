#import <Cocoa/Cocoa.h>
@class NoteObject;

extern NSString * const NVNoteContentsDidChangeNotification;
extern NSString * const NVNoteEditorDidChangeNotification;

// All editors for a note attach their own layout manager to this session's storage.
@interface NVNoteEditingSession : NSObject {
    NoteObject *note;
    NSTextStorage *textStorage;
    NSAttributedString *committedContents;
    NSAttributedString *pendingExternalContents;
    BOOL writingNote;
}
- (id)initWithNote:(NoteObject *)aNote;
- (NoteObject *)note;
- (NSTextStorage *)textStorage;
- (BOOL)canUndo;
- (BOOL)canRedo;
- (void)undo;
- (void)redo;
- (void)commitTextChanges;
- (void)commitPendingTextChanges;
- (void)reloadFromNote;
- (void)close;
@end
