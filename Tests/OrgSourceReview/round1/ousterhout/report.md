# Round 1: module and ownership review

This review uses a John Ousterhout-inspired perspective. It examines module boundaries and change amplification without impersonation.

No actionable Org-specific defect appeared in the reviewed boundaries.

The runtime probe passed **31 checks**, including four checks for copied-app and library isolation.
It ran production classes from the Development app on macOS 26.5.2, with Xcode 26.6.
The app used an Intel binary through Rosetta and a temporary notes library.
The probe did not substitute implementations of the syntax, editor, or session methods.

## Evidence

Run the successful boundary probe:

```sh
python3 Tests/OrgSourceReview/round1/ousterhout/run.py
```

The [probe](probe.inc) exercises these boundaries:

- A syntax menu action updates both editors through the note and its shared session.
- Org, JSON, and Plain Text transitions replace bracket-link behavior without stale Org labels.
- Syntax changes preserve live source, committed source, source generation, modification dates, and Undo history.
- An edit in the peer editor updates shared source and the explicit Org URL.
- Browser transitions detach their own layouts and preserve the cached editing session.
- Undo and external replacement rebuild Org links after both layouts detach.
- Reattachment uses the current source and syntax. A separate plain note retains its own nv links.

The [successful output](output.txt) records each assertion.
The [evidence manifest](evidence.json) records the source and executable hashes.
The launcher shares `build/pr-review/gui.lock` with other desktop probes.

## Observed limitation: visible-editor Undo

The initial probe replaced `Label` with `Résumé 😀` in a note open in two windows.
Undo failed with `Index 63 out of bounds; string length 60`.
The same source and edit failed in Plain Text with the same exception and call stack.

Run either control to reproduce the failure:

```sh
NV_OUSTERHOUT_UNDO_CONTROL=org python3 Tests/OrgSourceReview/round1/ousterhout/run.py
NV_OUSTERHOUT_UNDO_CONTROL=plain python3 Tests/OrgSourceReview/round1/ousterhout/run.py
```

Both controls return a failure status intentionally. They retain the visible editors during Undo.
Their logs are [Org](undo-org.txt) and [Plain Text](undo-plain.txt).
The stack reaches temporary-attribute invalidation during `replaceCharactersInRange:withAttributedString:` in `NVNoteEditingSession applyContents:`.
That character replacement precedes the new syntax-aware link call.

An equal-length edit also failed during temporary-attribute invalidation.
Its [output](undo-equal-length.txt) reports glyph generation while the text storage edits.
The first [failed run](undo-selection-failure.txt) remains available as additional evidence.

The successful boundary probe detaches both editors before Undo and external replacement.
It proves the session and link reconstruction paths under that condition.
It does **not** prove that visible-editor Undo works.
The Plain Text control establishes that this failure does not require Org syntax.
This review did not run the exact control against a baseline binary.

## Static review

The note remains the owner of local syntax metadata.
The session remains the owner of shared source and link attributes.
The browser routes syntax actions without acquiring separate source state.
The Org migration appends an extension and preserves the chosen output index.
The archive marker permits later removal of that extension.
The existing integration suite covers those migration cases. This review did not rerun that suite.

The syntax identifier appears in several existing allowlists and menus.
The Org change updates each relevant list and introduces no new owner.
A registry can reduce future edits, but this review found no missing entry that justifies a defect report.

Parser fidelity, large-note performance, and preview behavior are outside this probe's scope.
The source review compares the worktree with `f3a8abb2b7942d06ec33af64b4946cfd1b6db163`.
