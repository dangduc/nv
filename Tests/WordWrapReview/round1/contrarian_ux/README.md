# Round 1: contrarian editor behavior review

No new production defect was found in these three bounded behavior checks.
The reviewed revision is `4b049709b2cecc6eac80514586ccacc119d12802`, against `b6a5696`.

The approach temporarily narrows a line, then restores its rectangle.
This review challenges the assumption that Cocoa caret placement and selection remain consistent with that geometry.
The probe links the actual `NVSourceTypesetter.m` and extracts the actual glyph callback from `LinkingEditor.m`.
It uses disposable `NSTextView` instances with the common source paragraph style.
It does not reproduce the Core Text measurement or boundary algorithm.

The three hypotheses were:

1. A click in the blank remainder after a moved word can target the wrong source index.
   Character hit-testing, insertion hit-testing, selection rectangles, and native selection commands remained consistent in these cases.
   Every line retained its full container width.
2. Edits near wraps can leave stale caret positions or line boundaries.
   All 324 edit and resize snapshots matched fresh layouts, including every native insertion position.
   Insertions and Backspace preserved the intended source and selection.
3. A narrow view can split a fitting word or mishandle an oversized identifier.
   All 657 fitting words remained whole.
   The 51 observed splits in oversized tokens retained consistent hit-testing and selection.

Each production run passed 271,975 assertions on arm64 and x86_64 under Rosetta.
Each run included 108 initial layouts, 66,546 point samples, 1,226 blank-remainder clicks, and 99,765 native selection commands.
The commands were Right, Left, and Shift-Right.
The font matrix used Menlo, Helvetica, and Times New Roman at 18 points.
The nine widths ranged from 73.9 to 239.9 points, with pairs around several integer thresholds.
The source included prose, repeated spaces, tabs, line breaks, long identifiers, file paths, and ligature text.
The edit sequence also inserted a composed emoji.

The negative control removes only the custom typesetter.
It retains the production space callback and source paragraph style.
Each control run failed 204 fitting-word assertions and passed all other assertions.
This result establishes that the word-integrity checks distinguish the new behavior from the previous character layout.

Run from the worktree:

```sh
python3 Tests/WordWrapReview/round1/contrarian_ux/run.py
```

The runner records results and source identity in `results.json`.
It deletes temporary binaries after each run.
The host was macOS 26.5.2.
The compiler targets were macOS 11 for arm64 and macOS 10.13 for x86_64.

These are headless native API checks.
They do not cover painted frames, event dispatch, physical mouse input, an actual input method, or older macOS releases.
Some widths are narrower than a normal application editor pane.
The blank-remainder assertion covers complete word boundaries, not breaks inside oversized tokens or ligatures.
An initial filename-extension assertion treated `txt` within oversized `file.txt` as a separate word.
That assumption was incorrect, so the final fitting-word oracle uses complete whitespace-delimited words.
The probe created no windows and changed no personal notes, preferences, or production files.
