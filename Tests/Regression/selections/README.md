# Shared editor selection regression checks

After the Development build, run:

```sh
python3 Tests/Regression/selections/run-probes.py
python3 Tests/Regression/selections/run-negative-control.py
```

The GUI runner uses a copied app, temporary notes, a random preferences domain, and the shared GUI lock. Run outside the restrictive process sandbox.

The suite checks peer selections through undo, redo, external changes, overlapping replacements, multiple selections, and deferred merges.
Incoming rich attributes must leave source characters, selections, source generation, and Undo availability unchanged.
The editor must keep the current display font and discard authored styles.
Disjoint-change cases cover unchanged interior text, length changes, carets, repeated text, Unicode, and replacement of the selected text itself.
Overlap and fallback expectations use an independent Cocoa text view.

The native control compiles the actual editing session with an in-memory note.
Current code must emit separate edits around `core` in `AAcoreZZ` → `BBcoreYY` and discard incoming authored styles.
The negative control changes only snapshot application to use one replacement covering `core`; the same fixture must reject it.
The probe stubs display preferences, link detection, and parser layouts, which have separate integration tests.
It opens no windows and writes no notes.

## Snapshot mapping and limits

Snapshot application trims the common prefix and suffix, then searches for a shortest sequence of insertions and deletions inside the changed region.
It coalesces adjacent operations into replacements and applies separate spans from end to start.
Cocoa transforms each editor's selected ranges for each replacement.
A separate pass applies current display attributes and removes authored styles without expanding the character-change notification.

The search accepts at most 256 inserted or deleted UTF-16 code units and performs at most 1,000,000 frontier/comparison steps.
Exceeding either bound falls back to a single-range replacement.
Source characters still update; selections inside that broad replacement follow Cocoa's replacement behavior and can collapse.
Widely separated changes can exhaust the work bound even with a short edit script.

Common prefix/suffix anchors and a deletion-first tie rule make repeated-text alignment deterministic. The script does not infer which repeated occurrence the source application edited. It maps selections through its chosen edit spans instead of searching elsewhere for the selected string.

The independent `Tests/Regression/snapshot-diff/` tests check exhaustive and generated UTF-16 content reconstruction, reverse-order spans, and both bounds.
