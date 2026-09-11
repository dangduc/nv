# Round 1: glyph callback correctness and complexity

This review uses a Linus Torvalds-inspired engineering perspective. It is not a review by Linus Torvalds.

Reviewed commit: `9e6c8dd6adc058e7044f2c562532af97dd4e63d4`, against `75d6f4269d5c3f0ff2d3df392659ccf95bc1482b`.
No actionable finding arose in the examined boundaries at `Sources/Editor/LinkingEditor.m:289–331`.
Both arm64 and x86_64 passed 16,419 assertions on macOS 26.5.2 (25F84), with Xcode 26.6 (17F113).
The Intel run used Rosetta.

## Hypothesis 1: neighbor checks break the callback or buffer contract

The new neighbor reads follow the existing valid-space guard.
Empty sources cannot reach them, and the boundary conditions protect both adjacent reads.
The isolated-separator branch returns the native result without a property buffer.
The changed-batch branch retains the original glyph range, font, glyph IDs, and character indexes.
No new owner, editing callback, or shared cache is necessary for this local decision.

The new probe makes 1,936 synthetic calls per architecture across 15 explicit source fixtures.
Batch lengths are 0, 1, 2, 63, 64, 65, 127, and 257.
Sixteen rotations cover mixed combinations of the four defined glyph-property bits.
The glyph range starts at a nonzero location, while source indexes include repeated positions, the source end, and `NSNotFound`.

Fixture expectations name literal-space positions directly.
They do not reimplement the neighbor classifier.
The fixtures cover source edges, repeated spaces, tabs, NBSP, line separators, surrogate-pair neighbors, combining accents, variation selectors, and joiners.

The checks preserve every caller-owned input byte.
Modified batches install once, preserve glyph IDs and font identity, and return the installed glyph count.
Unchanged batches return zero, and batches without eligible properties make no source query.
Heap allocation uses exactly one property per glyph, and successful allocations have matching releases.
Sixteen injected allocation failures return the native fallback without a partial installation.
A separate oversized-count check returns before source or buffer access.

A one-glyph baseline control supplies only the separator glyph, with both source neighbors outside the batch.
The old callback installs a literal property, while the new callback returns zero and preserves native elasticity.

## Hypothesis 2: native fallback changes mappings or unrelated properties

Six native comparisons use three short or bounded strings with Menlo and Helvetica.
Each comparison includes native generation without a delegate, the baseline callback, and the corrected callback.
The runner extracts both complete callback bodies from the frozen commits and records their hashes.

Native generation reports Apple Color Emoji, Kohinoor Devanagari, PingFang SC, Menlo, and Helvetica.
Observed batch lengths range from one glyph to 257 glyphs.
Two actual 257-glyph batches require the corrected callback's heap buffer because they contain both separators and trailing spaces.

Glyph IDs, UTF-16 indexes, bidi levels, and normalized storage attributes match across all three variants.
The 266 property differences from the baseline contain only the intended separator Elastic bit.
Tabs, NBSP, attached-mark spaces, and all other property bits match the explicit fixture expectations.

The JSON also records native composed ranges for four edge strings.
Foundation reports the space and following accent, variation selector, or joiner as `{1, 2}` in the tested strings.
It reports `{1, 1}` for the space after U+0600 on this host.
These results describe Foundation's API behavior, not general Unicode grapheme conformance.

## Reproduction and limits

Run from the repository root:

```sh
python3 Tests/WrappedSeparatorReview/round1/torvalds/run.py
```

The adjacent `results.json` contains callback hashes, probe hashes, native fonts, batch counts, and both results.
Generated source, binaries, and logs remain in `build/WrappedSeparatorReview/round1/torvalds/`.
Each compile and native process has a 45-second timeout.

The synthetic sink records the native setter contract but is not an NSLayoutManager implementation.
Some synthetic flags and indexes need not occur in normal AppKit generation.
The separate native checks cover actual generation and fallback, before line layout.
They do not establish line geometry, caret behavior, marked-text composition, visible rendering, or the complete application event loop.
The probe does not establish behavior on older macOS versions or every font.
It creates no windows, reads no user notes or preferences, and changes no production files, commits, or PR comments.
