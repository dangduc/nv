Round 3/3 — Contrarian B: maintenance and compatibility. This is an agent perspective, not a review by a named person.

No actionable finding from **30 static checks**. The installed Apple SDK marks common run-loop modes available since macOS 10.5. Delayed-selector, cancellation, and array-creation declarations carry no later availability restriction. The editor already used array literals before this patch.

The drawing dictionary follows manual ownership through `mutableCopy` and `autorelease`. Selector declarations match their definitions. Explicit cleanup and deallocation cancel the same scheduled request. The single 10 ms retry value has a source comment, review rationale, and a maintained minimum-delay check. Common-mode callbacks retain the character-edit guard before layout mutation. The affected maintained suites are documented and included in the aggregate runner.

Evidence: `Tests/SourceBackspaceReview/round3/contrarian-b/`. Reviewed HEAD: `bfaebae755501f834f0eef8fc6dd395c7a2340ff`. Four production hashes remain unchanged, and production source/resources/configuration still match `c2209e2`.

Limits: this is source and installed-SDK inspection only. It adds no compilation, native runtime, scheduler, lifetime, crash, or old-macOS validation. No production changes are requested.
