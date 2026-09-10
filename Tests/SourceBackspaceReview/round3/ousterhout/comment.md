Round 3/3 — John Ousterhout-inspired static API review. This is an agent perspective, not a review by John Ousterhout.

P3 documentation clarification: `architecture.md:114` says note switches clear old backgrounds and cancel cleanup before changing storage. `removeHighlightedTerms` instead schedules another cleanup when character editing remains open, then returns. The attachment caller does not inspect that outcome. Please qualify the immediate guarantee to the non-editing path and describe the guarded deferral.

This is a documentation mismatch, not a demonstrated runtime bug. The static inventory otherwise supports the ownership split: the editor owns display invalidation and cleanup; the browser owns async-result generations and storage attachment. The new public invalidation method has a controller caller.

I wrote and ran a source-only Python inventory across 224 files. It records five API declarations/definitions, call sites, state references, and responsibility excerpts. Three static consistency checks pass. Commit `bfaebae` and four unchanged production hashes are recorded under `Tests/SourceBackspaceReview/round3/ousterhout/`.

No editor execution, lifecycle experiment, crash reproduction, or new native validation occurred in this round. Static text matching does not prove dynamic reachability or timing. macOS 13.7.8 remains untested.
