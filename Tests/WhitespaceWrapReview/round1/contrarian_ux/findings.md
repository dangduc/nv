# Round 1: Contrarian UX perspective

## P2: Keep a fitting word in place when trailing spaces overflow

Source: `Sources/Editor/LinkingEditor.m`, line 305, within the glyph adjustment at lines 294–305.
Reviewed commit: `83a7307`, against base `f772c4b`.

Clearing the elastic property changes native word breaks as well as space widths.
A new trailing space can move an existing word onto the next line, despite enough room for that word on its original line.
The first line then contains a short prefix and a large empty area.
Backspace reverses that movement.

The native key-event reproduction uses Plain Text, Menlo 18, and a 560-point window.
The text container is 544 points wide.
The source contains `alpha beta` followed by 39 ordinary spaces.
The probe sends one actual Space key event through `NSApp`, then calls native Backspace.

| State | Baseline `beta` origin | Candidate `beta` origin | Candidate caret |
| --- | --- | --- | --- |
| Before Space | (70.021, 0) | (70.021, 0) | (544.009, 8) |
| After the 40th space | (70.021, 0) | (5, 21) | (489.824, 29) |
| After Backspace | (70.021, 0) | (70.021, 0) | (544.009, 8) |

Word origins use text-container coordinates. Caret positions use text-view coordinates.
After Space, the candidate's first line contains only `alpha `.
Its second line contains `beta` and all 40 spaces.
The inserted character therefore moves the caret near the right side of the second line.
The source and logical selection remain correct throughout the sequence.

The requested change requires overflowing spaces to occupy more visual lines.
It does not require an already-fitting word to move with all its trailing spaces.
The implementation needs a break policy that preserves fitting words while the spaces wrap.
A correction must preserve source characters and normal word wrapping.
This review does not establish a safe replacement API or implementation.

## Other observations

The earlier screenshot observation reproduces against both complete app builds.
At Menlo 18 and width 560, `Start →` followed by 151 spaces moves the right arrow from `(70.021, 0)` to `(5, 21)`.
The baseline keeps the prefix on its first line and collapses the spaces at the margin.
The candidate starts the spaces beside the displaced arrow, then wraps them through subsequent lines.

Across the 12 font-and-width combinations, four ordinary-prose cases and eight double-spaced cases changed their line ranges.
Some differences follow directly from the newly occupied space widths.
Those comparisons support the scope of the change but do not constitute separate findings.
The P2 finding concerns the demonstrated displacement of an already-fitting word.

All 12 tab-and-nonbreaking-space comparisons retained identical baseline line records.
Native Left and Right visited every logical source position in the two navigation fixtures.
The sampled native insertion hit tests returned their original source positions.
No source mutation or selection-index failure occurred.

## Executed evidence

`run.py` loads a new Objective-C probe into a copied nvALT app.
It uses the real production editor, delegates, storage, and native navigation methods.
It does not replace or reproduce the glyph adjustment.
The runner holds `build/pr-review/gui.lock` and uses disposable notes, preferences, and support paths.

Each app completed 779 setup, source, navigation, and key-event checks.
Each run produced 141 records: 84 layout cases, 56 trailing-space thresholds, and one native key-event sequence.
The font fixtures use Menlo 12, 18, and 22, plus Helvetica 14.
The window widths are 480, 560, and 700 points.

`compare.py` rejects the candidate's premature word displacement with status 1.
The same comparison against baseline returns status 0.
The 0–55-space threshold series first displaces `beta` at 40 spaces in the candidate.
The baseline never displaces `beta` in that series.

Host: macOS 26.5.2 (25F84), with both Intel apps under Rosetta.
Candidate binary SHA-256: `6682e85cff4069c18b65ef9989830de2b72c3513240302a197395551d53d7d0c`.
Baseline binary SHA-256: `d2fc91aab87fbb3937073e11908832d177559761e46237ecd597a3bd9ca5ec80`.

The committed `results.json` contains both binary identities, the native key sequence, and the exact arrow fixture records.
Generated full geometry and logs remain in `build/WhitespaceWrapReview/round1/contrarian_ux/`.

## Reproduce

From the worktree, run:

```sh
python3 Tests/WhitespaceWrapReview/round1/contrarian_ux/run.py
python3 Tests/WhitespaceWrapReview/round1/contrarian_ux/run.py --label baseline \
  --app /Users/duc/dev/nv/build/TypingPerformanceWorktree/build/DerivedData/Build/Products/Development/nvALT.app
python3 Tests/WhitespaceWrapReview/round1/contrarian_ux/compare.py
python3 Tests/WhitespaceWrapReview/round1/contrarian_ux/compare.py --candidate-label baseline
```

The third command reproduces the finding and returns status 1.
The last command returns status 0 as the baseline control.

## Limits

The probe samples native insertion hit tests. It does not reproduce every mouse drag or physical pointer gesture.
The geometric checks do not measure every displayed animation frame.
This review does not cover all fonts, bidirectional text, accessibility navigation, or macOS 13.
