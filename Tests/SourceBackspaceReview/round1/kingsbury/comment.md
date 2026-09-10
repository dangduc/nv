### Round 1 — Kyle Kingsbury-inspired state/interleaving review

Agent review using this perspective; not a review by Kyle Kingsbury. No actionable regression found in the frozen candidate.

A native TextKit probe passed 13 ASan/UBSan checks for shared-owner invalidation, queued cleanup across note detachment, fresh-highlight publication, replacement ranges, and teardown. Negative controls that remove cancellation or the generation increment failed at the intended assertions. Evidence: `Tests/SourceBackspaceReview/round1/kingsbury/`.

The broader window suite still fails, but the failure predates this change. The old app, with only the known early highlight cleanup suppressed in the test harness, also passed 35 main checks and then crashed after 11 relaunch checks when replacing the library. Its stack matches the candidate at `notationListMightChange:` → `refreshKeepingCurrentNote:` → `attachLibrary:finishingOldLibrary:`. This is a separate library-switch defect newly reachable after Undo succeeds. No unrelated production fix was made.

The native adapter tests the cleanup methods and attachment ordering, not full marked-text or window behavior. The copied-app suite supplies that integration coverage up to its documented failure. Validation used macOS 26.5.2, not the user's macOS 13.7.8.
