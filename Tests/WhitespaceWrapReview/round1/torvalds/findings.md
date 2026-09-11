# Round 1: systems correctness

No actionable finding was found in the 28-line glyph delegate method at `83a7307`, compared with `f772c4b`.
This review uses a systems-correctness perspective. It does not attribute the review to Linus Torvalds.

## Executed evidence

`run.py` extracts the exact production method from `Sources/Editor/LinkingEditor.m:286` into a small Objective-C harness.
The harness does not duplicate the method's implementation. Its allocation wrappers add failure injection and poison the scratch buffer before release.
The result file records the extracted method's SHA-256 hash.

Both arm64 and x86_64 runs passed 4,755 assertions with AddressSanitizer and UndefinedBehaviorSanitizer.
Each run compared 4,220 native glyphs across eight fixtures. These fixtures produced 772 delegate batches and 388 changed batches.
The runs detected no sanitizer error. The host runs macOS 26.5.2 with Xcode 26.6.

The focused checks cover:

- Zero-length and multiplication-overflow batches return zero before access to the supplied buffers.
- Read-only arrays end immediately before inaccessible memory pages. The method preserves all three input arrays.
- The glyph batch has a nonzero location. The method preserves the range, glyph pointer, character-index pointer, and font identity.
- An eligible batch allocates exactly one complete property array. A successful call releases that array.
- A failed allocation returns zero without a partial store. A batch without eligible spaces allocates nothing.
- Explicit expected values preserve ControlCharacter, Null, NonBaseCharacter, and an additional property bit.
- Boundary indexes include the first character, the final character, the source length, and NSNotFound.
- Synthetic arrays include repeated character indexes and indexes within UTF-16 surrogate sequences.

The native comparison uses real NSTextStorage, NSLayoutManager, and font substitution. Its baseline has no glyph delegate.
The candidate calls the extracted production method through an audit delegate.
The comparison preserves glyph IDs, UTF-16 character indexes, bidirectional levels, and source characters.
Only the Elastic bit differs, on 1,524 eligible U+0020 glyphs per architecture.

Native glyph readback occurs after the production method poisons and releases its temporary property array.
The correct readback supports synchronous consumption by `setGlyphs:` on this host.
The property-array recorder also checks the complete expected output after the scratch buffer's release.

## Contract review

The installed AppKit SDK states that each supplied array contains `glyphRange.length` entries.
It permits repeated character indexes and directs delegate implementations to return zero for default glyph generation.
The production loop indexes the arrays relative to the batch, while each character index addresses the full UTF-16 source.
The method preserves the complete index array and calls `setGlyphs:` only inside the glyph-generation callback.
It does not query surrounding glyph information or calculate a glyph-range endpoint.

The property-size guard prevents multiplication overflow. Source bounds precede `characterAtIndex:`.
The method borrows its source string from the manager's text storage for the synchronous callback.
The normal allocation and allocation-failure paths have matching ownership behavior.

The SDK contract is in `NSLayoutManager.h`, lines 179–180 and 389–391, under the active macOS SDK.
Apple also publishes the [delegate reference](https://developer.apple.com/documentation/appkit/nslayoutmanagerdelegate/layoutmanager(_:shouldgenerateglyphs:properties:characterindexes:font:forglyphrange:)).
The installed SDK comments supplied the readable contract for this review.

## Limits

The native fixtures include decomposed accents, joined emoji, ligatures, Arabic, Hebrew, Devanagari, Chinese, tabs, and Unicode spaces.
They produced 382 NonBaseCharacter glyphs per architecture.
They produced no repeated character indexes and no unequal total glyph and UTF-16 counts on this host.
Therefore, the repeated-index evidence comes from synthetic batches, not native font output.
The synthetic flag combinations and invalid indexes are defensive inputs. They are not claims about normal AppKit output.

An initial harness assertion incorrectly required native fixtures to produce repeated indexes and unequal counts.
The final harness records those counts and retains direct synthetic checks for repeated indexes.
The production method passed the native output comparisons before that harness correction.

These checks do not establish behavior for every font, writing system, or older macOS version.
They do not measure wrapping geometry, caret movement, undo, shared windows, or performance.
No application window opened, and no note library or preference domain was accessed.
The native framework binaries are not sanitizer-instrumented. Leak detection is disabled for these short AppKit processes.
Objective-C exception injection into `setGlyphs:` is outside this review's valid-callback scope.

## Reproduction

Run this command from the worktree:

```sh
python3 Tests/WhitespaceWrapReview/round1/torvalds/run.py
```

The small results are in `results.json` and `output.txt` beside this report.
Generated source, binaries, and architecture logs are in `build/WhitespaceWrapReview/round1/torvalds`.
No production source, commits, or remote state changed during this review.
