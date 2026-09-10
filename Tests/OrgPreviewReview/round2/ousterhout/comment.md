### Round 2 — John Ousterhout-inspired review

No actionable viewer API or ownership defect found.
The reviewed state is `415cf69` plus the frozen fragment fix in `PreviewController.m`.
Provider SHA-256: `e786f468b82d7ae45c59adb3aed5123bcaa6dc3b757145ead9b219e90b79436a`.

I wrote and ran a new copied-app probe: **43 assertions passed**, including four launch-isolation checks.
Empty-note commands keep allocation lazy. Unknown, numeric, and missing saved viewer identifiers retain a supported format without changing source or peer state.
Restoring a missing note closes only that window's provider.

Two actual Org WebKit documents then changed to different heading fragments and offsets, with periodic state timers inactive.
Concurrent public capture calls returned each window's actual offset and separate Find query exactly once.
The source storage remained shared, and source metadata, characters, generation, dates, and Undo history stayed unchanged.
The fix preserves the existing capture ownership and revision boundaries while accepting fragment-only navigation.

Evidence: `Tests/OrgPreviewReview/round2/ousterhout/{run.py,probe.inc,output.txt,evidence.json,report.md}`.
The run used macOS 26.5.2, Xcode 26.6, and the Intel app through Rosetta.
It does not cover app relaunch, physical link clicks, the complete URL-variant matrix, broad Org fidelity, performance, composition, or edited-source Undo.
