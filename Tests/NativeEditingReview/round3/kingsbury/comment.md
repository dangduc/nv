**Round 3 — Kyle Kingsbury-inspired review: one P2 finding.**

`NVNoteEditingSession` owns and observes the one `NSTextStorage` shared by every window, but `sourceCharactersChanged:` only advances the syntax generation. `LinkingEditor.m:500-543` still computes a range in one window and rebuilds link attributes from that view's `didChangeText` callback.

The executable 20-check two-window probe demonstrates the ownership gap: a character mutation delivered through the session's shared text storage reached both editors and committed to the model, but its new URL had no link attribute. The next URL, inserted through the foreground `LinkingEditor`, was linked immediately. Move incremental link removal/rebuilding into `NVNoteEditingSession.sourceCharactersChanged:` using the post-edit `editedRange`, expanded to complete lines, and the session's note syntax. Then remove `changedRange`, `shouldChangeTextInRange:replacementString:`, `didChangeText`, and the associated typing-attribute repair from the view.

The same probe found no additional failures in per-window finder isolation, independent layouts, cross-layout search invalidation, asynchronous syntax generations, or Undo/Redo after closing the edit-originating window. Evidence is in `Tests/NativeEditingReview/round3/kingsbury/`.
