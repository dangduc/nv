# Round 1 — Kyle Kingsbury review

## Result

No actionable findings.

I reviewed the native-editing simplification as a state machine whose durable
value is the note model, whose mutable coordination point is one
`NSTextStorage`, and whose clients are independently attached window layouts.
The review focused on operations that can cross those boundaries: marked-text
composition, peer-window mutations, global Undo/Redo, search-highlight
invalidation, asynchronous syntax publication, and layout detachment.

## Evidence

`run.py` builds `probe-body.m` as an injected x86_64 test bundle and runs it in
a disposable copy of the Development app with a disposable note library. The
probe executed 20 assertions:

- two windows shared exactly one session text storage but retained distinct
  layout managers;
- initial Markdown highlighting reached the same current revision in both
  layouts;
- search backgrounds remained layout-local and a source mutation invalidated
  them in both layouts;
- a native edit reached the peer editor and the note model;
- syntax highlighting reconverged after the native edit;
- a marked-text edit followed by a direct peer mutation was serialized by
  TextKit, committed without losing characters, and reversed/restored as one
  shared Undo/Redo transaction;
- detaching one peer layout during marked text left the remaining editor and
  session live, and the final commit and highlighting completed;
- 40 alternating edits across the two native editors converged in both views
  and the model, and 40 shared Undo operations reversed all 40 characters in
  order.

Commands executed:

```sh
python3 Tests/NativeEditingReview/round1/kingsbury/run.py --compile-only
python3 Tests/NativeEditingReview/round1/kingsbury/run.py
```

Both commands passed. The app probe ended with:

```text
KINGSBURY ROUND 1 PASSED (20 checks)
```

## Validation limits

The composition transition uses AppKit's `setMarkedText:` API and native
`NSTextView` mutation methods. It does not drive a physical keyboard or a
specific third-party input method. All editor and model transitions run on the
main thread, as required by AppKit; the asynchronous syntax worker is observed
through its published layout revision rather than instrumented internally.
