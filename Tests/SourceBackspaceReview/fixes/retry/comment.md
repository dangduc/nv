Resolved the round 1 Dan Luu-inspired P2 finding about zero-delay retries.

`removeHighlightedTerms` now requests a 10 ms delay while character editing remains open.
The first invalidation still uses zero delay. Stale backgrounds remain suppressed until safe cleanup.
The character-edit guard and cancellation selector remain intact.

The dedicated AppKit probe passed **20 checks**.
An open edit scheduled **5 callbacks in approximately 50 ms** in each of the default and event-tracking modes.
Each workload completed one safe removal after the edit ended.
The zero-delay negative control failed at its expected assertion.
The maintained HighlightBounds suite passed **134 checks each** in native, Intel, and native ASan/UBSan builds.
All **11 mutation controls** failed as expected.

Evidence: `Tests/SourceBackspaceReview/fixes/retry/` and `Tests/FuzzySearch/HighlightBounds/`.
The dedicated probe uses production methods with real AppKit storage, layout, and timers in an editor adapter.
It covers suppression, foreground preservation, cleanup, and cancellation before fresh publication or storage replacement.
It opens no GUI app and does not cover macOS 13.
Production hashes stayed unchanged during validation.
