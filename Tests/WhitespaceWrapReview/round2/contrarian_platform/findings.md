# Round 2: contrarian platform and text compatibility

No introduced corruption or selection-mapping failure was found at reviewed commit `072a6bc0f54a52603f8cedfbcacc17d0ab836a36`.
The current character-wrap style and glyph delegate produce no line boundary inside a composed-character sequence in this matrix.

## Executed evidence

The runner extracts the current shared-style block and complete glyph delegate from production source.
It checks their reviewed hashes, independently of later documentation or evidence commits.
The results record both the reviewed commit and actual checkout.

The x86_64 native run passed 19,193 assertions on macOS 26.5.2 with Xcode 26.6.
It contains 48 fixture/font/width matrices, each with three native NSTextView layouts:

1. Default native word wrapping, without a glyph delegate.
2. The production shared character-wrap style, without a glyph delegate.
3. The production shared style and production glyph delegate together.

The font requests are Helvetica 18 and Times 18. Container widths are 18, 35, 62, and 120 points.
The narrowest containers are smaller than some individual glyph clusters.
Native callbacks report eight fonts, including emoji, Arabic, and Devanagari fallback fonts.

The six fixtures cover:

- Decomposed Latin accents and trailing ordinary spaces.
- Emoji skin tones, joined emoji, a family sequence, regional-indicator flags, and a keycap sequence.
- Devanagari conjuncts and vowel signs, including a joiner.
- Hebrew, Arabic, Latin digits, and joined emoji with an explicit right-to-left writing attribute.
- Tabs, NBSP, and U+2002/U+2003 spaces without ordinary spaces.
- Latin ligatures, including fi, fl, ffi, and ffl.

## Preserved invariants

Every variant preserves its complete source string.
Glyph IDs, UTF-16 character indexes, bidirectional levels, and final native font attributes match across all three variants.
The glyph delegate changes only Elastic on eligible ordinary-space glyphs.
The marker attribute remains intact across the source, and every character retains a native font attribute.

All current line starts occur at NSString composed-character boundaries.
There are zero observed cluster splits across the 48 current layouts.
Logical selections at every composed-character boundary remain at the requested source index.
Layout and hit-test queries preserve the initial selection.

The eight protected-whitespace comparisons preserve the native character-wrap control's glyph properties and complete line records.
This result separates intentional character-wrap reflow from any additional effect of the glyph delegate on tabs or nonbreaking spaces.

## Native insertion hit tests

The probe samples the public NSTextView insertion hit test every four points across each line.
It makes 3,204 such calls in current layouts. Every returned source position is within bounds.
The controls receive the same sampling procedure for their own line geometry.

The Indic fixture returns some insertion offsets inside NSString composed-character sequences.
Those offsets also occur in the native word-wrap or native character-wrap control for the same font and width.
The current variant introduces no additional interior offset in this sampled comparison.
The result contains 32 distinct-per-case interior-offset records across the eight Indic matrices.
No other fixture returns an interior composed-character offset.

These observations do not support a claim that every native insertion hit always returns a grapheme boundary.
They also do not establish a new invalid mapping from this change.
The result files retain the complete unique interior-offset sets for all three variants.

## Harness correction and limits

The initial harness assumed that every storage font attribute retained the requested font.
Native setup replaces unsupported fonts with fallback fonts in these fixtures.
The final harness compares the resulting font attributes across native controls and current code instead.
This correction concerns a test assumption, not a production source change.

The run uses in-memory AppKit objects and no application window, user library, or user preference domain.
It does not measure rendered pixels, keyboard traversal, input-method composition, or every possible mouse position.
The grid comparison does not prove that different layouts map the same screen coordinate to the same source offset.
Different line breaks are intentional in this revision.
Clusters wider than their container receive native layout behavior. The probe makes no clipping or visual-overflow guarantee.

NSString supplies the composed-character boundaries for this host.
The fixtures do not establish behavior for every Unicode sequence, font, writing system, or macOS version.
macOS 13 remains untested.

## Reproduction

```sh
python3 Tests/WhitespaceWrapReview/round2/contrarian_platform/run.py
```

The runner holds `/Users/duc/dev/nv/build/pr-review/gui.lock` during native execution.
Small results and the output log are beside this report.
Generated source and the binary remain under `build/WhitespaceWrapReview/round2/contrarian_platform`.
No production file, commit, or remote state changed during this review.
