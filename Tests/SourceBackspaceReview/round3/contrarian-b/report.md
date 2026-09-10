# Round 3 — Contrarian B: maintenance and compatibility

This is an agent perspective. It is not a review by a named person.

No actionable finding. The available source and SDK evidence show no new deployment requirement, ownership mismatch, or undocumented retry policy that warrants a change in this patch.

## Evidence

Run `python3 -B Tests/SourceBackspaceReview/round3/contrarian-b/run.py` from the repository root.

The script passed **30 static checks**. It reads project source, Git metadata, documentation, test source, and installed Apple SDK headers. It writes only the output and manifest in this review directory.

Reviewed HEAD: `bfaebae755501f834f0eef8fc6dd395c7a2340ff`. Final production commit: `c2209e2e6ca1194c3a3ffe361e826860e4e830d8`. All four production hashes matched before and after the review. No content in `Sources`, `Resources`, `Config`, or `Notation.xcodeproj` changed after that production commit.

`manifest.json` preserves exact SDK declarations, header hashes, source hashes, and each check result. `output.txt` preserves the inventory output.

## Compatibility assessment

The stored Xcode configurations specify macOS 10.9. The documented Development command and CI command override that target to macOS 10.13. This difference predates the patch and is not a new finding.

The installed Apple `NSRunLoop.h` marks `NSRunLoopCommonModes` available since macOS 10.5. Its delayed-selector and cancellation declarations have no later platform-availability restriction. The `NSArray` object/count creation declaration also has no later restriction in the installed header.

The base editor already contains two array literals. The new common-mode list therefore uses existing language syntax. The inspected declarations and preexisting syntax support compatibility with the project's stated build targets. This is a source assessment, not execution on an old operating system.

## Ownership and maintenance assessment

The only new copied object is the temporary drawing dictionary. Its `mutableCopy` is paired with `autorelease`, which follows the surrounding manual ownership model. New persistent state is a primitive Boolean. The project does not enable ARC, and superclass deallocation remains present.

The new invalidation selector and scheduled cleanup selector each have a matching declaration and definition. Explicit cleanup and editor deallocation cancel the same target, selector, and object request. Note attachment cleanup remains part of the final production patch; later review commits do not change it.

The 10 ms value appears once in production. It applies only when cleanup encounters open character edits. Initial invalidation still coalesces requests and schedules its first callback separately. Both paths use the same common-mode list. The edit-mask guard remains before layout mutation, so the source does not rely on the selected run-loop mode alone for safety.

The source comment explains why retries avoid zero delay. The review index documents the change to 10 ms and links its rationale. The maintained HighlightBounds fixture checks the positive minimum delay and eventual cleanup. Architecture documentation explains deferred removal and cancellation by fresh highlights. The retry is an internal scheduling choice, not a documented completion deadline.

I found no need to introduce a configuration option or a shared constant for this single production use. Such changes would add an interface without a demonstrated requirement.

The test index links the copied-app suite and its command. The aggregate runner includes both SourceBackspace and HighlightBounds. Contributors can find the affected maintained tests without replaying historical review scripts.

## Limits

This round is **source-only**. It performs no compilation, native application execution, crash reproduction, altered variant, or new runtime validation. It does not measure scheduler timing, reference lifetimes, rendering, or operation on macOS 10.9, 10.13, or the user's macOS 13.7.8.

The absence of a newer availability annotation is evidence from the installed SDK, not an independently established introduction date for every API. Historical runtime behavior remains outside this review.
