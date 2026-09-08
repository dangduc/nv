# Round 3: deletion and shared editing ownership

No actionable defect introduced by this PR was found in this scope.
This review uses a John Ousterhout-inspired focus on ownership boundaries; it does not represent his participation or endorsement.

## Code reviewed

The review compared `9693356..f9cc501` and read `architecture.md` before writing the probe.
Removing `DeletedNoteObject.originalNote` and the remote deletion set does not remove local deletion Undo ownership.
`NotationController.removeNote:` retains its argument during removal, registers `addNewNote:` on the library Undo manager, and then releases the temporary retain.
The application also caches editing sessions by UUID until library replacement or termination.
The cached session may therefore survive deletion, but its removed note must leave every live browser editor.

The focused paths are:

- [Local deletion and Undo registration](../../../../Sources/Storage/NotationController.m).
- [UUID session cache and browser lifecycle](../../../../Sources/Application/NVApplicationController.m).
- [Browser Delete and editor attachment](../../../../Sources/Browser/AppController.m).
- [Shared source and metadata history](../../../../Sources/Editor/NVNoteEditingSession.m).
- [Journal tombstone identity](../../../../Sources/Model/DeletedNoteObject.m).

The round-one fixture correction in `b418d84` changes test provenance and archive precondition checks.
It does not change these production paths. The production executable is unchanged from `f38a8cb`.

## Original executable evidence

[checks.inc](checks.inc) drives real browser windows, source editors, and native title/tag fields.
Delete dispatches through the application coordinator to the active browser.
Deletion Undo and Redo use the native responder chain with the notes list focused.
The probe verifies that the window selects the actual library Undo manager before dispatch.

It runs three histories:

1. Both browser editors display the note when it is deleted.
2. The peer switches to an unrelated note before deletion.
3. The peer closes after deletion and reopens after deletion Undo/Redo/Undo.

Each history first records four note edits: source from the first window, title, source from the peer, and tags.
The body includes Unicode, CRLF, a tab, and markup characters.
After browser deletion, both editors leave the removed text storage and the storage has zero attached layout managers.
The peer's unrelated note remains unchanged in the second history.
An application metadata command for the removed note is rejected.

Deletion Undo restores the same model identity, UUID, local syntax, title, tags, exact source, and cached editing session.
Deletion Redo removes the note and detaches its layout again.
A second Undo restores it, and the surviving or reopened peer attaches to the same text storage.
The probe then undoes all four note edits in order and redoes them from the peer editor.
Each step compares both editors, the model body, title, and tags against explicit expected values.
The final local library flush succeeds.

| Run | Result | Evidence |
| --- | --- | --- |
| Current app | 154 assertions pass; three histories | [current.log](current.log) |
| Baseline app | 154 assertions pass; same histories | [baseline.log](baseline.log) |
| Current app with deletion Undo registration omitted | Exits 1 when native Undo fails to restore the same model and active selection | [omitted-undo.log](omitted-undo.log) |

[prefix.h](prefix.h) implements the optional sensitivity control entirely within the disposable app process.
It replaces `_registerDeletionUndoForNote:` with a no-op; the normal runs do not install that replacement.
The mutation still reports `canUndo`, so `canUndo` alone is not the oracle.
The explicit post-command model membership and selection check detects the missing deletion restoration.
No production file was modified for the control.

## Reproduction and attribution

Run from the repository root in an active macOS desktop session:

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/SimplenoteRemovalReview/round3/ousterhout/checks.inc \
  --prefix Tests/SimplenoteRemovalReview/round3/ousterhout/prefix.h \
  --app build/SimplenoteRemovalReview/round1.app

python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/SimplenoteRemovalReview/round3/ousterhout/checks.inc \
  --prefix Tests/SimplenoteRemovalReview/round3/ousterhout/prefix.h \
  --app build/SyntaxFlickerReview/fix.app

NV_R3_OMIT_DELETION_UNDO=1 python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/SimplenoteRemovalReview/round3/ousterhout/checks.inc \
  --prefix Tests/SimplenoteRemovalReview/round3/ousterhout/prefix.h \
  --app build/SimplenoteRemovalReview/round1.app
```

The last command must exit 1 at the restoration assertion.
The runner copies the app, uses temporary notes and preferences, and serializes desktop use with the shared GUI lock.
It does not use an actual account, network sync, or user notes.

| Executable | SHA-256 |
| --- | --- |
| Current frozen app, production `f38a8cb` | `d61aea6619f6c4322efac164d7409ac131aa0ce2a8760d874850c34443331ede` |
| Baseline frozen app, production equivalent to `9693356` | `ee8e9ca27c99d55ff867afabd49e75c12f5548f49ac93dc733f514f477cac365` |

Both apps passed the same assertions. This comparison produced no behavior that needs classification as a preexisting failure.
The probe compiled under the repository's Intel Cocoa test configuration without warnings after a local test variable rename.

## Limits

These histories cover committed edits, single-note deletion, database storage, two browser windows, and normal writes.
They do not cover input-method composition at the moment of deletion, batch deletion, file conversion sheets, failure injection in storage, or process-crash recovery.
Other review probes cover several of those boundaries.
This probe verifies live editor detachment and history behavior; it does not claim that the UUID cache immediately releases deleted notes or that process memory is bounded.
It does not invoke private session editing methods on a removed note after all browser layouts have detached.
