# Shared editor selection regression checks

After the Development build, run:

```sh
python3 Tests/Regression/selections/run-probes.py
python3 Tests/Regression/selections/run-negative-control.py
```

The GUI runner uses a copied app, temporary notes, a random preferences domain, and the shared GUI lock. Run outside the restrictive process sandbox.

The suite checks peer selections through undo, redo, external changes, overlapping replacements, multiple selections, style updates, and deferred merges. Disjoint-change cases cover unchanged interior text, length changes, carets, repeated text, Unicode, and replacement of the selected text itself. Overlap and fallback expectations use an independent Cocoa text view.

The native negative control compiles the actual editing session with an in-memory note. Current code must emit separate edits around `core` in `AAcoreZZ` → `BBcoreYY`. The same test rejects reviewed head `3502c7c`, which emits one edit covering `core`. This control requires that commit in local Git history. It opens no windows and writes no notes.

## Snapshot mapping and limits

Snapshot application trims the common prefix and suffix, then searches for a shortest sequence of insertions and deletions inside the changed region. It coalesces adjacent operations into replacements and applies separate spans from end to start. Cocoa transforms each editor's selected ranges for each replacement. A separate attribute pass applies all style runs without expanding the character-change notification.

The search accepts at most 256 inserted or deleted UTF-16 code units and performs at most 1,000,000 frontier/comparison steps. Exceeding either bound falls back to the previous single-range replacement. The text and attributes still update; selections inside that broad replacement follow Cocoa's replacement behavior and can collapse. Widely separated changes can exhaust the work bound even with a short edit script.

Common prefix/suffix anchors and a deletion-first tie rule make repeated-text alignment deterministic. The script does not infer which repeated occurrence the source application edited. It maps selections through its chosen edit spans instead of searching elsewhere for the selected string.

The independent `Tests/Regression/snapshot-diff/` tests check exhaustive and generated UTF-16 content reconstruction, reverse-order spans, and both bounds.
