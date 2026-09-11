# Round 1: layout history consistency

No additional actionable finding. All 128 checks passed at commit `4b049709b2cecc6eac80514586ccacc119d12802`.
All 40 observed layouts matched fresh production layouts.
The runner left the production files unchanged.

This review uses a Kyle Kingsbury-inspired focus on histories and invariants. It does not represent Kyle Kingsbury.

## Evidence

The runner injects independent checks into a copied Development app.
The copy uses disposable notes, a private preference domain, and isolated support and temporary directories.
The runner acquires the main checkout's `build/pr-review/gui.lock` before it starts the app.

The checks exercise actual `AppController`, `LinkingEditor`, `NVNoteEditingSession`, and `NVSourceTypesetter` objects.
Native editing, Undo, Redo, note selection, resize, and marked-text APIs drive the histories.
The startup isolation comes from `Tests/MultipleWindowsTests.m`. The history checks are new.

The comparison uses a fresh layout manager and the app's linked `NVSourceTypesetter` class.
It copies the observed source attributes, container geometry, typing attributes, font-leading setting, typesetter behavior, and hyphenation factor.
The actual source editor supplies its production glyph delegate.
The comparison contains no word-break implementation.

Every comparison checks character ranges, glyph ranges, line rectangles, used rectangles, glyph positions, and any extra line fragment.
The line ranges must cover every source character exactly once.
At each committed state, both editors and the note model must contain the expected source.

| History | Sequence | Result |
| --- | --- | --- |
| H1 | Insert a prefix paragraph, split a cached paragraph from the peer, cross window widths, edit the final paragraph, then Undo and Redo every edit. | All expected source states and 20 layout comparisons passed. |
| H2 | Switch between equal-length sources with different word boundaries, pass through an empty note, then Undo from the attached peer and return. | The peer stayed unchanged during switches. All 10 layout comparisons passed. |
| H3 | Compose replacement text, resize and detach the peer, replace the composition, resize the first editor, reattach the peer, then commit, Undo, and Redo. | Pending source stayed shared. The model retained committed source until composition ended. All 10 layout comparisons passed. |

The fixtures contain ASCII prose, Vietnamese text, Chinese text, combining marks, emoji sequences, tabs, ordinary spaces, and paragraph separators.
Observed source lengths ranged from 0 to 369 UTF-16 units.
Observed container widths were 464, 629, 799, and 809 points.

## Run

From the worktree root, run:

```sh
python3 Tests/WordWrapReview/round1/kingsbury/run.py
```

For compilation without a desktop app, run:

```sh
python3 Tests/WordWrapReview/round1/kingsbury/run.py --compile-only
```

The `--app` argument accepts another absolute app path.
The run requires an active desktop session. The sandboxed app launch aborted before any check, so the recorded run used desktop permission.

## Recorded result

- macOS 26.5.2, build 25F84.
- Xcode 26.6, build 17F113.
- Intel app through Rosetta.
- App SHA-256: `10d1c49332562935a883e9c16d8e58adb4d67cc833bc34e066b4082db898de95`.
- 128 checks passed, 40 layout comparisons passed, process exit status 0.
- `results.json` records source hashes before and after the run.
- `observations.json` records every history checkpoint and its line geometry.
- `app.log` records every assertion. `compile.log` is empty because compilation produced no diagnostics.

## Harness corrections and limits

The first comparison included the origin of an absent extra line fragment.
TextKit retained different zero-size origins after layout. The final comparison includes extra geometry only when the container owns an extra fragment.

The initial empty-note comparison omitted typing attributes and used a 14-point line height instead of the editor's 21-point height.
The final comparison copies typing attributes to a native text view. These were comparison errors, not production findings.

Fresh-layout equality detects dependence on prior edits or cached layout state.
It cannot detect a deterministic wrapping error that affects both layouts equally.
This run does not assess positive tail indents, natural RTL alignment, cache memory retention, or performance with long paragraphs.
An empty-note layout match does not prove that the typesetter released its previous paragraph cache.

The composition checks use native marked-text methods. They do not run a physical input method or candidate window.
The resize checks set window sizes through AppKit. They do not simulate a physical divider drag or inspect compositor pixels.
This run does not establish behavior on macOS 13.7.8.
