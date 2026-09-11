# Round 3 UX review

No actionable finding in this bounded review.

The optimized glyph hook is from frozen commit `e022109eaf2bad6583512c2ed2b48561d9dae011`.
The comparison uses the previous hook from `2ea92180939a3e51df8fe867ad548140ed455868` and the original literal-space hook from `75d6f42`.
The runner compiles these exact methods with the production typesetter, which is identical across all three revisions.

Run from the repository root:

```sh
python3 Tests/WrappedSeparatorReview/round3/ux/run.py
```

The new probe uses six composition histories in headless native `NSTextView` instances.
Menlo and Helvetica run at the measured first-word width, with offsets of minus 0.25, zero, and plus 0.25 points.
Each history changes the word after a single space through `x`, `e\u0301`, `\u0301x`, `雪`, and `x`, then commits.
The leading accent attaches to the space and makes that space literal.

All four runs passed 300 checks on macOS 26.5.2: optimized and previous hooks on arm64 and x86_64.
Each run covers 36 states, 36 fresh-layout comparisons, 30 native word-wrap insertion comparisons, and six protected-space measurements.
Source, logical selection, caret affinity, marked ranges, and separator elasticity match the expected states.
Full pre/post transcripts match within each architecture, including native line rectangles and insertion positions.
All six protected states match the original literal-space policy's full layout and insertion positions.

The first run assumed that an accented space's insertion interval equals an unmarked font space's width.
That assertion failed in one state per run: Menlo at minus 0.25 points measured 11.6982421875 points, versus 10.8369140625 points for an unmarked space.
The same state matches the original literal-space policy exactly.
The final probe compares that complete layout with the original policy and checks that the insertion interval remains positive.
This was a fixture assumption, with no regression found.
The measured intervals remain in `results.json`.

The runner reuses setup helpers from the Round 1 and Round 2 UX probes and the original word-wrap review.
It does not rerun their matrices.
No production files, user notes, app preferences, or GUI windows were changed.
This probe exercises marked-text APIs directly.
It does not cover input-method event dispatch, painting, older macOS versions, or the full application's editing history.
