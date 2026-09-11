# Source word wrapping

The standalone probe links the production `NVSourceTypesetter.m`.
The runner extracts the current space glyph delegate from `LinkingEditor.m`.
The probe uses disposable Cocoa text systems and one temporary window.
It does not open the note library or change application preferences.

Run the suites from an active macOS desktop session:

```sh
python3 Tests/WordWrapping/run.py
```

The default includes arm64 and x86_64 on Apple Silicon.
On Intel, the default includes x86_64 only.
The Intel deployment target is macOS 10.13. The arm64 target is macOS 11.0.
The window suite uses the repository's shared `build/pr-review/gui.lock` across worktrees.

For a single architecture or suite, use these arguments:

```sh
python3 Tests/WordWrapping/run.py --arch x86_64 --suite editing
python3 Tests/WordWrapping/run.py --negative-control
```

The negative control removes the custom typesetter but retains the current space glyph delegate and character wrapping.
The prose assertion must reject this previous behavior.

The suites cover these behaviors:

- `matrix`: fitting words remain whole across 108 font, size, width, and paragraph settings. Appended spaces preserve existing word rows.
- `matrix`: Unicode fixtures include combining marks, emoji, Chinese, Hebrew, tabs, and nonbreaking spaces. Line boundaries preserve composed characters.
- `geometry`: glyph positions match native word layout on identical lines, with natural, left, right, and center alignment.
- `editing`: native Space events, Backspace, and marked text preserve source and selection. Space overflow advances the caret.
- `editing`: interior edits and width changes produce the same glyph positions and line boundaries as a fresh text system.
- `performance`: initial layout of 4,096 to 32,768 characters, for spaces, unbroken letters, and prose.

Geometry comparisons exclude lines with different native boundaries.
These exclusions reflect the two wrapping modes. They do not establish geometry equivalence for those lines.
The timing suite measures layout only. It omits source setup and result collection from each timed interval.
Each measurement contains six samples after one warmup. Timings have no pass threshold.

## Recorded results

The suites passed on 2026-09-11 with macOS 26.5.2 (25F84) and Xcode 26.6 (17F113).
Intel runs used Rosetta on the same host.

| Suite | arm64 checks | x86_64 checks |
| --- | ---: | ---: |
| Matrix | 51,425 | 51,425 |
| Geometry | 3,145 | 3,145 |
| Native editing | 19,476 | 19,476 |
| Performance completion | 168 | 168 |

Each geometry run compared 2,992 glyph positions on identical lines.
Each run excluded 528 positions on different lines.
Both negative controls failed at the expected fitting-word assertion.

For 32,768 spaces, median initial layout took 4.94 ms with word wrapping and 4.15 ms with previous character wrapping on arm64.
The Intel medians were 12.78 ms and 7.94 ms respectively.
The Intel samples showed substantial variation. These observations do not establish a performance bound.

The runner writes JSON evidence to `build/WordWrapping/`.
The current evidence does not include macOS 13.7.8, physical key input, or the complete nvALT event loop.
