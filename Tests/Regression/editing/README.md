# Editing history regression checks

Build the Development app into `build/DerivedData`, then run:

```sh
python3 Tests/Regression/editing/run-probes.py
```

The runner copies the app and uses temporary notes and a separate preferences domain. Run it outside the restrictive process sandbox.

The suite checks ordinary undo and redo, undo from another browser during composition, disjoint and overlapping external edits, repeated undo, redo invalidation, and menu validation.

Editor history actions use `NVNoteEditingSession` to finish marked text in all attached views before changing history. Deferred external updates establish a history checkpoint. Older whole-note snapshots cannot remove the external update on a later undo. Overlapping changes preserve an external conflict copy.

The note's raw `NSUndoManager` remains available for internal use after editing has finished. Calling it directly bypasses composition finalization; UI actions must use the session methods.
