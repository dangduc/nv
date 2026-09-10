### Round 3 review — John Ousterhout perspective

I ran `python3 Tests/NativeEditingReview/round3/ousterhout/run.py`; the compiled
AppKit prototype passed nine checks.

**Medium — finish the native editor boundary.** `LinkingEditor.m:500-543` still
overrides `shouldChangeTextInRange:replacementString:` and `didChangeText` only
to compute an affected line and rebuild link attributes. It obtains syntax by
walking from the view to its browser's selected note. `NVNoteEditingSession`
already owns the note and shared `NSTextStorage`, and already observes processed
character edits. The prototype shows that this observer gets the exact
post-edit `editedRange`, can expand it to the complete line, distinguish
character edits from attribute-only display work, and rebuild decoration after
both insertion and deletion.

Move incremental link maintenance into `NVNoteEditingSession`, using its note's
syntax, then delete the editor's `changedRange`, `sourceSyntaxIdentifier`,
`shouldChangeTextInRange:replacementString:`, `didChangeText`, and
`fixTypingAttributesForSubstitutedFonts`. This makes the whole edit lifecycle
native while keeping shared source decoration with the shared-storage owner.

**Low — delete dead surface.** `highlightRangesTemporarily:` has no production
caller; the active search path uses `setSearchHighlightRanges:`. Remove its
header declaration and implementation.

Validation limit: the prototype uses real AppKit text storage but is not
injected into the full GUI. Run the source-editing and shared-window suites after
moving ownership.
