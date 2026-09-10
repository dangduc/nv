#import <Cocoa/Cocoa.h>
#import "NVSourceAnalysis.h"
@class NoteObject, NVNoteMetadataUndoTarget, NVSourceHighlighter;

extern NSString * const NVNoteContentsDidChangeNotification;
extern NSString * const NVNoteEditorDidChangeNotification;
extern NSString * const NVNoteWordCountDidChangeNotification;

// All editors for a note attach their own layout manager to this session's storage.
@interface NVNoteEditingSession : NSObject <NVSourceAnalysisDelegate> {
    NoteObject *note;
    NSTextStorage *textStorage;
    NSAttributedString *committedContents;
    NSAttributedString *pendingExternalContents;
    NVNoteMetadataUndoTarget *metadataUndoTarget;
    BOOL writingNote;
    NVSourceHighlighter *sourceHighlighter;
    uint64_t sourceGeneration;
    NSFont *sourceFont;
    NVSourceAnalysis *sourceAnalysis;
    NSHashTable *wordCountClients;
    NSUInteger wordCount;
    uint64_t wordCountGeneration;
    BOOL closed;
}
- (id)initWithNote:(NoteObject *)aNote;
- (NoteObject *)note;
- (NSTextStorage *)textStorage;
- (uint64_t)sourceGeneration;
- (void)sourceLayoutDidAttach;
- (void)sourceLayoutDidDetach;
- (void)setWordCountRequested:(BOOL)requested forTextView:(NSTextView *)view;
// Returns the last accepted count for this note, which may lag during typing.
- (BOOL)getWordCount:(NSUInteger *)count;
- (BOOL)canUndo;
- (BOOL)canRedo;
- (void)undo;
- (void)redo;
- (void)setMetadataValue:(NSString *)value isTitle:(BOOL)isTitle;
- (void)commitTextChanges;
- (void)commitPendingTextChanges;
- (void)reloadFromNote;
- (void)close;
// Used after the library's final checkpoint, when committing again is unsafe.
- (void)closeWithoutCommitting;
@end
