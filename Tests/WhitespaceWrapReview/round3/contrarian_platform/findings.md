# Round 3: contrarian platform and text compatibility

No semantic regression was found in the buffer optimization at reviewed commit `4b725372670afd5f5ecadf512deba8498336b2f0`.
The live native comparison produces equivalent results with the old and new production callbacks.

## Executed evidence

The runner extracts the old glyph method from `072a6bc0f54a52603f8cedfbcacc17d0ab836a36` and the current method from the working source.
It checks the current fragment against the reviewed commit and records both hashes.
Both variants use the exact current shared-style block from GlobalPrefs.
The results record the actual checkout separately, so later evidence commits do not prevent reproduction.

The x86_64 native run passed 56,330 assertions across 28 dynamic phases on macOS 26.5.2 with Xcode 26.6.
Each variant has one NSTextStorage shared by two NSTextViews, with separate layout managers and different container widths.
Thus, every phase compares four live views and two independent source storages.
The test does not create application windows.

## Dynamic sequence

The sequence starts with 63 ordinary spaces and containers of 62 and 180 points.
It repeats this edit cycle three times:

1. Native insertion in alternating views grows the source to 64 and then 65 spaces.
2. A further insertion grows the source to 257 spaces.
3. Native Backspace removes a selected suffix and returns the source to 63 spaces.
4. Native insertion adds a prefix with a combining accent, joined emoji, Hebrew, Indic text, a tab, and NBSP.
5. Native Backspace removes the selected complete emoji cluster.
6. A font-attribute change triggers native glyph and fallback-font regeneration.
7. Both text containers receive different new widths.
8. A native replacement returns the mixed-script source to 63 spaces.

The font changes use Helvetica 14, Times 18, and Menlo 22.
The width cycles range from 30 to 240 points.
Native callbacks report nine fonts, including emoji and Devanagari fallback fonts.

The callback histogram contains lengths 63, 64, 65, 66, 201, 202, 212, and 257, along with smaller batches.
This confirms native execution across the stack threshold and repeated large/small regeneration.
The old and new histograms match in this run.

## Preserved invariants

After every phase, both storages contain the exact expected source string.
Old and new callbacks produce identical glyph IDs, properties, UTF-16 indexes, and bidirectional levels in both views.
The complete native attribute dictionaries match at every source position.
The metadata marker remains present, and the shared character-wrap policy remains active.
This comparison includes the protected tab and NBSP characters while the Unicode prefix exists.

Native selection ranges remain in bounds and match between old and new variants after all edits and regeneration.
Every measured line starts at an NSString composed-character boundary.
Line ranges and geometry match, with a tolerance of one millionth of a point for coordinates.
Glyph positions also match with that tolerance.

The probe makes 12,298 native insertion hit-test calls across all four variants.
It samples each line every eight points across the container width.
Every returned source index is in bounds, and the complete hit-index arrays match between old and new callbacks.
This comparison covers hit-test behavior after source edits, font fallback, and width changes.

These observations support semantic equivalence of the buffer optimization for the tested live sequence.
The test does not require a particular word-wrap policy: both callbacks intentionally use the current character-wrap style.

## Limits

The test uses native NSTextView insertion and deletion methods, not posted hardware-key events or the complete nvALT application lifecycle.
No visible rendering, input-method composition, accessibility, or printing claim follows from this run.
The sampled hit-test equivalence does not cover every possible point or keyboard navigation command.
The test compares old and new behavior. It does not classify native Indic interior caret positions as a new error.

The matrix covers selected fonts, Unicode clusters, and repeated batch transitions on one macOS version.
macOS 13 remains untested.
The documented many-paragraph resize cost and intentional character-based word splits remain outside this equivalence result.

## Reproduction

```sh
python3 Tests/WhitespaceWrapReview/round3/contrarian_platform/run.py
```

The runner holds `/Users/duc/dev/nv/build/pr-review/gui.lock` during native execution.
Small results and the output log are beside this report.
Generated source and the x86_64 binary remain under `build/WhitespaceWrapReview/round3/contrarian_platform`.
No user notes, preferences, production files, commits, or remote state changed during this review.
