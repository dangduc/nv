# Round 2: cleanup and editor interaction

No new defect was found in these two focused sequences.
The corrected revision is `4c8f6b449504a50caa460d78efebd42b94beaba6`.
The control uses the actual typesetter from revision `4b049709b2cecc6eac80514586ccacc119d12802`.

The first sequence deletes all wrapped content, checks the empty insertion line, then restores and resizes the text.
It repeats three times with each font, including a source that contains only two paragraph breaks.
All six empty states retained finite caret-line geometry and insertion index zero.
Restoration preserved the exact source and final insertion index.

The second sequence moves across CRLF, LF, U+2028, and U+2029 separators.
It then inserts and deletes spaces, LF, CRLF, and a composed emoji at four positions in a wrapped identifier.
Arrow navigation and selection preserved native separator semantics.
Every insertion and Backspace preserved the intended source and caret.

Each corrected run passed 17,712 assertions on arm64 and x86_64 under Rosetta.
Each run covered 32 layout snapshots, 4,340 point samples, 32 blank-remainder clicks, and 6,504 selection commands.
Thirty additional commands exercised paragraph separators.
The fonts were Menlo and Helvetica at 18 points.
The container widths were 160.1 and 239.9 points.

All incremental snapshots matched fresh layouts, including line rectangles and every native insertion position.
The complete geometry, source, and selection transcript matched the prior revision exactly on both architectures.
The runner compares transcript hashes and fails on any difference.

The observer forwarded 100 paragraph completions per run.
The corrected typesetter retained no analysis after those callbacks.
The prior typesetter retained analysis after 82 callbacks.
This control establishes that the sequences exercise the changed cache lifetime without an observed interaction change.

The probe includes the [round-one helpers](../../round1/contrarian_ux/probe.m) and replaces their matrix with these two sequences.
It links production source directly and reuses the glyph scanner from `Tests/WordWrapping/run.py`.
It does not duplicate the layout algorithm.
The separator selection oracle uses native `NSTextView` without the custom typesetter.
Cocoa movement and Shift-Right selection treat CRLF differently, so a composed-string range alone is not that oracle.

Run from the frozen worktree:

```sh
python3 Tests/WordWrapReview/round2/contrarian_ux/run.py
```

The runner records source hashes and results in `results.json`.
It deletes temporary binaries after the run.
The host was macOS 26.5.2.
The compiler targets were macOS 11 for arm64 and macOS 10.13 for x86_64.

These headless native API checks do not cover painted frames, physical input, event dispatch, actual input methods, or older macOS releases.
They do not exercise shared-note window ownership.
The probe created no windows and changed no personal notes, preferences, or production files.
