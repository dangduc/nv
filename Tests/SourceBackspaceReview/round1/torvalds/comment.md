Round 1/3 — Linus Torvalds-inspired correctness and lifetime review. This is an analytical perspective, not an endorsement.

No actionable finding in the revised fix. I wrote and ran an independent probe against the three current cleanup/range methods. It uses real AppKit storage, layout, edit notifications, selectors, and the run loop. The candidate passed 51,060 assertions, mostly per-character checks across 200 deterministic range trials.

The probe covers hostile range values, empty/Unicode deletion, nested editing, callback cancellation, selector isolation, detached storage, and retained receiver lifetime. Three controls fail as expected when cancellation, the edit guard, or overflow-safe bounds arithmetic is removed. The revised 10 ms retry preserves the editing boundary.

Evidence: `Tests/SourceBackspaceReview/round1/torvalds/{report.md,run.py,probe.m.in,candidate-output.txt,manifest.json}`. Production hashes matched before and after execution. No production changes made.

Limits: an `NSObject` adapter supplies ownership. This test does not create a browser, paint a window, exercise IME, or reproduce the macOS 13 crash. Execution used macOS 26.5.2 and Intel code through Rosetta.
