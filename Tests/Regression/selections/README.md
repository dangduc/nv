# Shared editor selection regression checks

After the Development build, run:

```sh
python3 Tests/Regression/selections/run-probes.py
```

The runner uses a copied app, temporary notes, a random preferences domain, and the shared GUI lock. Run outside the restrictive process sandbox.

The suite checks peer selections through undo, redo, external suffix and prefix changes, overlapping replacements, multiple selections, attribute-only updates, and deferred external merges. Overlap and multiple-selection expectations use an independent Cocoa text view with the intended character edit.

Snapshot application changes the differing characters first. A separate attribute update then applies all style runs. Keeping these edit batches separate prevents full-document style ranges from expanding the character-change notification.
