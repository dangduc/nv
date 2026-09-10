# Round 2 — Kyle Kingsbury-inspired review

## Result

No actionable finding at `7ed3d684418f7f311433d12fb20d14f34c60154a`.

The executable probe passed 21 checks in a disposable, injected copy of the
Development app. It treated the note editor as a shared-state system rather
than as one `NSTextView`:

- two windows shared one `NSTextStorage` while retaining independent layout
  managers;
- 48 edits alternated between windows while first responder, syntax type, and
  search overlays changed;
- the final JSON generation displaced queued Markdown, HTML, JSON, and plain
  highlighter work in both layouts;
- search backgrounds were removed from both layouts after a shared character
  mutation;
- an external write during marked-text composition waited, merged with a
  disjoint local insertion, and produced an Undo baseline that retained the
  external write;
- both layouts detached while syntax work was queued, then a replacement
  highlighter converged after both layouts reattached;
- the window that originated an edit closed before Undo and Redo; the remaining
  window and model still converged.

`run.py --compile-only` also passed. The runtime command was:

```sh
python3 Tests/NativeEditingReview/round2/kingsbury/run.py
```

## Review notes

The initial lifecycle fixture used 1,200 repeated headings. That exceeded the
highlighter's deliberate limit of 4,096 temporary-attribute writes across all
attached layouts, so a current display revision was not expected. The final
fixture uses 160 headings, stays below that public implementation bound, and
still detaches the last layout before the queued 60 ms analysis begins. This was
a probe correction, not an application defect.

## Limits

This is deterministic transition coverage on one macOS/Xcode host. It does not
simulate real IME key events, thread-sanitizer scheduling, process termination
mid-write, or long-running fuzz input. It verifies the app's explicit external
update API and TextKit lifecycle, but it does not model file-system edits that
bypass `NoteObject` notifications.
