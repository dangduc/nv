# Round 3 — Kyle Kingsbury-inspired review

## Result

One actionable shared-state finding at
`4265d28a9aa0193a31f14b39d6f0c4c61d533deb`.

### P2 — move incremental link maintenance into `NVNoteEditingSession`

`NVNoteEditingSession` owns the one mutable character store used by every
window and observes every character edit in `sourceCharactersChanged:`
(`NVNoteEditingSession.m:150-152`). It increments the source generation there,
but does not maintain the `NSLinkAttributeName` invariant. Instead,
`LinkingEditor.m:500-543` computes an affected range in a window-local ivar and
rebuilds shared link attributes from `didChangeText`.

The executable probe exposed the split ownership. It directly mutated the
session's `NSTextStorage`, which delivered the new characters to both attached
windows and was successfully committed to the note model. The inserted URL had
no link attribute. Inserting a second URL through the foreground
`LinkingEditor` immediately added its link attribute. Shared characters should
not have decoration correctness depend on which client performed the mutation.

Move the incremental remove-and-rebuild step to
`NVNoteEditingSession.sourceCharactersChanged:` when the edited mask contains
`NSTextStorageEditedCharacters`. Expand the post-edit `editedRange` to complete
lines and use the session's note syntax. Remove `changedRange`,
`shouldChangeTextInRange:replacementString:`, `didChangeText`, and the remaining
typing-attribute repair from `LinkingEditor`. This gives every mutation one
serialized owner and leaves each window responsible only for its layout.

## Other observed boundaries

The 20-check app probe found no additional shared-session failures:

- two windows shared one `NSTextStorage` and retained separate layout managers;
- finder-hide notifications from one browser did not close the other browser's
  native find bar;
- source edits invalidated search backgrounds in both layouts;
- the final JSON syntax generation displaced older asynchronous work;
- closing the window that originated an edit left Undo and Redo available in
  the remaining window, with view and model contents converged.

Commands executed:

```sh
python3 -B Tests/NativeEditingReview/round3/kingsbury/run.py --compile-only
python3 -B Tests/NativeEditingReview/round3/kingsbury/run.py
```

Both passed. `output.txt` records the runtime result.

## Validation limits

The known orphaned `IBeamInverted.png` project membership blocks the prescribed
fresh build at this revision; this review does not duplicate that finding. The
runtime probe used the current review Development product built with that
missing resource excluded. It uses deterministic TextKit mutations and does
not simulate physical keyboard input, process termination, or arbitrary
filesystem races.
