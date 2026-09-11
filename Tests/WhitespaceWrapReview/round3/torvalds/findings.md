# Round 3: systems correctness

No actionable safety finding was found in the scratch-storage change at reviewed commit `4b725372670afd5f5ecadf512deba8498336b2f0`.
This review uses the requested systems-correctness perspective. It does not attribute the work to Linus Torvalds.

## Executed evidence

The runner extracts the complete current glyph method and current shared-style installation block.
It compares both fragments with the reviewed commit, so later evidence commits do not prevent reproduction.
The results record actual HEAD, reviewed HEAD, and both fragment hashes.

Both arm64 and x86_64 passed 8,843 assertions under AddressSanitizer and UndefinedBehaviorSanitizer.
AddressSanitizer's stack-use-after-return mode is enabled at compilation and execution.
Neither run reported a sanitizer error.
The host runs macOS 26.5.2 with Xcode 26.6.

Each architecture executes 361 guarded cases, including 256 deterministic mixed-index cases.
The fixed cases repeat lengths 63, 64, 65, 257, 64, and 1 through three cycles.
These transitions repeatedly reuse the stack after large heap batches.

## Scratch-boundary checks

The caller's glyph, property, and character-index arrays are read-only and end immediately before inaccessible memory pages.
Each stored result must match an independently specified expected property array after stack clobbering.
Glyph and character-index pointers, font identity, and a nonzero batch range remain unchanged.

The cases cover:

- A last-entry eligible space at lengths 63, 64, and 65.
- An early property candidate that maps to a nonspace, followed by a later actual space.
- Elastic control properties with no eligible candidate and no source-storage access.
- Elastic non-control properties that all map to nonspaces and require no scratch allocation.
- Zero length and multiplication overflow, with no manager or accessible arrays.
- Injected heap-allocation failure for large eligible batches, with no partial store.
- Injected allocation failure during small batches, which still succeed through the stack path.
- Repeated source indexes, low-surrogate indexes, combining-character indexes, source-length indexes, and NSNotFound.
- Control, Null, NonBaseCharacter, and an additional property bit.

The property test uses explicit expected cases rather than calculating expectations with the production condition.
The deterministic generator combines those cases at lengths from 1 through 257.
It records 100 successful synthetic stack stores and 199 successful heap stores per architecture.
Every large allocation uses the complete required byte count, and the failure cases leave the caller arrays intact.

## Native scratch lifetime

The native stage uses real NSTextStorage and NSLayoutManager objects with the current shared character-wrap style.
It compares the production delegate with a native control that has no glyph delegate.
The fixtures include space batches at 63, 64, 65, and 257 entries, plus combining text, joined emoji, Indic text, tabs, and NBSP.

An audit layout manager calls the public superclass `setGlyphs:` implementation first.
After that call returns, it poisons the production caller's private scratch array.
The original AppKit property buffer remains untouched.
This models the caller reusing scratch memory after the public store returns.
A separate non-inline function clobbers 8 KiB of stack before subsequent readback.

Each architecture exercises 18 native stack stores and six native heap stores across repeated fixture sequences.
The subsequent comparison covers 1,416 glyphs.
Glyph IDs, UTF-16 character indexes, and bidirectional levels remain identical to the native control.
Observed property differences contain only the expected removal of Elastic from ordinary spaces.
The source strings remain unchanged.

These checks support synchronous consumption of both scratch paths by the public native store on this host.
They also show that one call's property values do not contaminate a later call in the tested sequence.

## Inspection

The property prescan checks its batch bound before every property access.
It does not inspect source indexes or source storage until an eligible property candidate exists.
A property candidate alone does not allocate memory: its mapped character must also be an ordinary space.

The stack branch accepts at most 64 entries, based on the array's element count.
The heap branch retains the multiplication-overflow guard.
The full property copy initializes the prefix before the first candidate as well as the remaining batch.
The final pointer comparison prevents free from receiving stack storage.
The method does not retain either scratch pointer after the public store.

## Limits

The guarded inputs are defensive test cases. They are not claims that AppKit normally supplies invalid indexes or synthetic flag combinations.
The native frameworks are not sanitizer-instrumented, and leak detection is disabled.
The native poisoning/readback comparison supplies additional evidence for the framework boundary.
It does not prove correct behavior on every macOS release.

The run uses in-memory native objects without windows, user notes, or preferences.
It does not measure caret drawing, line-wrap policy, performance, or macOS 13 behavior.
The documented many-paragraph resize cost remains outside this safety check.

## Reproduction

```sh
python3 Tests/WhitespaceWrapReview/round3/torvalds/run.py
```

The runner explicitly reuses the round-1 recorder, guarded-allocation helper, and native snapshot helper.
The new case generator, scratch-transition checks, native poisoning audit, and stack clobbering are in this round's probe.
Small results and logs are beside this report. Generated products remain under `build/WhitespaceWrapReview/round3/torvalds`.
No production source, commit, or remote state changed during this review.
