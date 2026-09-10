Round 2 of 3 — Dan Luu-inspired review of costs and measurements. This is an analytical perspective, not an endorsement by Dan Luu.

No actionable finding. The 10 ms retry delay corrects the round 1 busy loop in this workload. Repeated invalidations do not defeat that delay. Fresh results cancel the pending retry and retain their backgrounds.

The new probe extracts five production methods. These cover invalidation, cleanup, range publication, drawing attributes, and the shared-storage observer. It uses native AppKit storage, layout managers, timers, and run loops. Editor and controller ownership use small `NSObject` adapters.

The probe runs 12 workloads across 1, 4, and 16 attached editors. Each workload holds two nested editing batches open, then closes the inner batch during the experiment. The outer batch stays open for about 300 ms. The run loop alternates between default and event-tracking modes. Both modes belong to the common-mode set.

Evidence:

- During each workload, three bursts issue 10,000 invalidations per editor. Each burst adds zero schedules while a retry is pending. Background removal remains zero throughout the open outer batch.
- Every retry requests at least 10 ms. All callbacks use common modes. The workloads recorded about 30 schedules per editor during the open batch. At 16 editors, each workload recorded 496 schedules, including the initial zero-delay callback for each editor.
- A 1 ms heartbeat timer continued to run. These measurements show bounded retry scheduling for the workload; they do not establish a general responsiveness limit.
- After the outer batch closes, every attached controller receives one character-change notification. The observer advances each generation once.
- One publication order installs fresh ranges before the pending retry can run. It performs one cleanup per editor and cancels the retry. Both fresh ranges survive subsequent turns in both modes.
- The other order lets cleanup finish before fresh publication. It performs two removals per editor: the completed cleanup and the setter's normal cleanup. Fresh publication adds exactly two backgrounds per editor. No retry chain remains active.
- Pending drawing suppresses the obsolete background while preserving foreground attributes and the input dictionary. No temporary background removal occurs during a character-edit batch.

The production probe passed **1,794 checks**. Two mutation controls confirm that the checks can detect the relevant regressions:

1. Restoring the zero-delay retry failed the requested-delay assertion. It scheduled 25,374 zero-delay retries during one 300 ms batch.
2. Removing cancellation failed the cleanup-count and fresh-background assertions. The old retry ran after publication and erased the new ranges.

Run `python3 Tests/SourceBackspaceReview/round2/luu/run.py`. Results are in `production.txt`, the two mutation logs, and `manifest.json`. Compilation produced no diagnostics. The manifest records HEAD `feef9bd95ceb4f3b05d2a5cb00622c1b269ea4d9`; production code is from `c2209e2`. All four production file hashes stayed unchanged throughout the run.

Limits: the Intel executable ran through Rosetta on macOS 26.5.2. It opened no app, window, or user notes. It does not cover real event routing, rendered pixels, or the macOS 13.7.8 environment in the crash report. The prolonged editing batch is deliberate. Its frequency in normal editing is unknown. Assertions use operation counts, requested delays, and attribute state. Elapsed measurements are descriptive, not performance thresholds.
