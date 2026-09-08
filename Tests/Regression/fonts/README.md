# Source display font regression

After the Development build, run:

```sh
python3 Tests/Regression/fonts/run-probes.py
```

The test uses a temporary library and a copied application with separate preferences.
The runner serializes desktop access with `build/pr-review/gui.lock` and limits the application process to 90 seconds.

The checks cover current, hidden, cached, and previously unopened notes.
Font and foreground changes preserve model attributes, source bytes, modification dates, journal sequence numbers, source generations, and existing Undo history.
The test records note-write and sync-push requests during each display change.
It also executes existing Redo and Undo operations after a font change.

The live editor uses the current display font without changing unopened model records.
A font change defers its display update during input-method composition.
Composition completion applies the new font and preserves the composed characters.

The earlier probe remains in `Tests/ReviewEvidence/round1/torvalds/` as historical evidence.
Its model-restyling expectation no longer applies to source notes.
