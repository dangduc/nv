# Round 2: systems correctness

No actionable finding was found at frozen commit `072a6bc0f54a52603f8cedfbcacc17d0ab836a36`.
This is a systems-correctness review inspired by the requested perspective. It is not a review by Linus Torvalds.

## New executed evidence

`run.py` extracts two current production fragments: the complete glyph delegate and the shared-style installation block from GlobalPrefs.
The results include a SHA-256 hash for each fragment.
The harness reuses the round-1 buffer helpers and adds adversarial checks for the current style integration.
It does not reproduce either production fragment by hand.

Both arm64 and x86_64 passed 4,894 assertions under AddressSanitizer and UndefinedBehaviorSanitizer.
The runs detected no sanitizer error.
The host runs macOS 26.5.2 with Xcode 26.6.

The new style checks cover:

- A dispatch_apply group makes 64 parallel calls to the extracted installation block, each with its own dictionary.
- Every caller receives the same non-nil style pointer and observes NSLineBreakByCharWrapping.
- The published object is immutable. The system default paragraph style retains word wrapping.
- Changes to a mutable copy cannot alter the shared style's wrapping, alignment, direction, or indentation.
- Two independent native text storages initially share the immutable style.
- Replacing one storage's paragraph style leaves the other storage and the shared constant unchanged.
- A font-attribute refresh restores the shared wrapping policy in the modified storage.
- Full attribute normalization and an empty-storage boundary preserve the complete source.
- The shared style remains valid after caller dictionaries are cleared and local autorelease pools drain.

The font-refresh and normalization checks use the same public attribute operations as the editing session.
They do not call the complete session controller methods.
This isolates style ownership and attribute propagation from unrelated application state.

## Current glyph invariants

The native glyph comparisons now install the current production style in both the baseline and candidate storage.
The baseline has no glyph delegate. The candidate calls the exact extracted production method.
Each architecture compares 4,220 glyphs across 772 callbacks.
The candidate changes 1,524 ordinary-space glyphs in 388 callbacks.

Glyph IDs, UTF-16 character indexes, bidirectional levels, and source characters remain identical.
Every property difference removes only Elastic from an eligible U+0020 glyph.
The native readback remains correct after the scratch array is poisoned and released.
Read-only guarded arrays cover exact boundaries, allocation failure, multiplication overflow, and nonzero batch locations.
Explicit expected arrays cover repeated indexes, surrogate indexes, control flags, combining flags, and an additional property bit.

The native fixtures produce 382 NonBaseCharacter glyphs per architecture.
They produce no repeated character indexes or unequal total glyph and UTF-16 counts.
The evidence for those cases remains synthetic.

## Ownership and API inspection

The static once token has static zero initialization. dispatch_once publishes the configured object before subsequent callers continue.
The initializer copies a mutable paragraph style into an immutable object, then releases the mutable object.
The retained immutable copy has process lifetime. Dictionaries retain their references to that same object.
No caller receives the temporary mutable object.

The glyph delegate still receives one entry per glyph, preserves the input pointers except for copied properties, and returns the full stored batch length.
Its zero-length and size-overflow guards precede buffer access. Its source bounds guard precedes UTF-16 character access.
The change adds no pointer-size assumption, private API, source substitution, or glyph-index translation.

The existing retained-dictionary behavior in noteBodyAttributes predates this change and is outside this round's findings.
The shared style does not allocate a new paragraph style for every call.
Character wrapping and its ordinary-word splits are intentional policy in this revision.

## Limits

The parallel test exercises only the extracted style block with independent dictionaries.
It does not assert that the complete GlobalPrefs getter is safe for concurrent calls.
Scheduler behavior can serialize initial publication. The code inspection supplies the dispatch_once initialization argument.
ThreadSanitizer and leak detection were not used. ASan and UBSan do not establish absence of data races in native frameworks.
The native framework binaries are not sanitizer-instrumented.

The harness uses in-memory AppKit objects. It opens no application window, note library, or user preference domain.
It does not cover macOS 13, full application lifecycle, every writing system, or visible editing behavior.
The report makes no new geometry or performance claim.

## Reproduction

```sh
python3 Tests/WhitespaceWrapReview/round2/torvalds/run.py
```

The script requires the reviewed fragment hashes and records the actual checkout and reviewed commit separately.
Small results and logs are beside this report. Generated source and binaries remain under `build/WhitespaceWrapReview/round2/torvalds`.
No production source, commit, or remote state changed during this review.
