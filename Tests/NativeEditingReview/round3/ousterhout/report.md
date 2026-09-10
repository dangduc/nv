# Round 3 — John Ousterhout review

## Result

The Round 2 cursor and finder cleanup removed the process-wide side effect and
most compatibility branches. Ordinary source commands now belong to
`NSTextView`, and `LinkingEditor` retains real view responsibilities for syntax
drawing, search backgrounds, links, colors, selection presentation, native find,
and width management. One edit-lifecycle responsibility is still on the wrong
side of the view/session boundary.

## Finding

### O3 — Medium: move incremental link maintenance to the editing session

`LinkingEditor.m:500-543` still overrides `didChangeText` and
`shouldChangeTextInRange:replacementString:`. The latter computes a complete
affected-line range in the view and stores it in the `changedRange` ivar. The
former removes and rebuilds links in that range, using
`sourceSyntaxIdentifier` at line 28 to recover note identity through the
view's browser controller.

This splits one source invariant across two owners. `NVNoteEditingSession`
already owns the note, the shared `NSTextStorage`, and the syntax identifier,
and already observes `NSTextStorageDidProcessEditingNotification` in
`sourceCharactersChanged:`. Link attributes also belong to the shared storage,
not to either window's view. The current design therefore makes every native
edit pass through view-specific pre/post hooks only to update session-owned
state.

Move the remove-and-rebuild pass into `NVNoteEditingSession` when its observed
storage reports `NSTextStorageEditedCharacters`. Use the post-edit
`editedRange`, expanded with `lineRangeForRange:`, and the session's `note`
syntax. Then remove `LinkingEditor`'s `changedRange` ivar,
`sourceSyntaxIdentifier`, `shouldChangeTextInRange:replacementString:`,
`didChangeText`, and `fixTypingAttributesForSubstitutedFonts`. The existing
session font refresh, editor setup, and responder setup already own the typing
appearance. This leaves AppKit in control of the complete edit lifecycle while
the session owns all shared source decoration.

### O4 — Low: delete the orphaned legacy range-highlighting entry point

`highlightRangesTemporarily:` is declared in `LinkingEditor.h` and implemented
in `LinkingEditor.m`, but has no production caller. The only third occurrence of
its name is its own error log. Delete the declaration and implementation. The
current asynchronous search path uses `setSearchHighlightRanges:`.

## Executable evidence

Run:

```sh
python3 Tests/NativeEditingReview/round3/ousterhout/run.py
```

The Python checks assert that the retired command overrides, global cursor
swizzle, and hidden tab-width policy remain absent from the actual production
source. It also confirms that the two edit-lifecycle overrides and their
`changedRange` state remain, and inventories the orphaned highlight method.

The compiled AppKit probe passed nine checks. A storage owner observed a native
insertion and deletion through `NSTextStorageDidProcessEditingNotification`,
received the exact post-edit range, expanded it to the affected line, rebuilt a
link attribute, ignored an attribute-only notification as source input, and
held syntax identity without consulting a view controller. This is executable
evidence that the session boundary has all information needed by the remaining
view hooks.

## Validation limits

The probe exercises AppKit's real text-storage notification and attribute
machinery in a command-line process. It does not inject the prototype into the
complete nvALT GUI or exercise Tree-sitter and link decoration concurrently.
Those paths need the existing source-editing and shared-window suites after the
ownership move. No production code changed during this review.
