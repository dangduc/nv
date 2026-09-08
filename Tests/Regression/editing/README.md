# Editing history regression checks

Build the Development app into `build/DerivedData`, then run:

```sh
python3 Tests/Regression/editing/run-probes.py
```

The runner copies the app and uses temporary notes and a separate preferences domain. Run it outside the restrictive process sandbox.

The suite checks ordinary undo and redo, undo from another browser during composition, disjoint and overlapping external edits, repeated undo, redo invalidation, and menu validation. It also checks unchanged external snapshots and discarded external formatting during composition.
External font, underline, and strikethrough attributes do not enter source history.
Their removal preserves composed characters, existing Undo and Redo operations, and both peer editors.

Background reveal checks cover stale lists and queries that exclude the requested note.
A new matching note must appear without a query reset or window activation.
Both editors must select the requested note before the shared Undo checks begin.

Editor history actions use `NVNoteEditingSession` to finish marked text in all attached views before changing history. Deferred external updates establish a history checkpoint. Older whole-note snapshots cannot remove the external update on a later undo. Overlapping changes preserve an external conflict copy.

The note's raw `NSUndoManager` remains available for internal use after editing has finished. Calling it directly bypasses composition finalization; UI actions must use the session methods.
