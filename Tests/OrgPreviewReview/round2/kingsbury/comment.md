## Preview review round 2 — fragment navigation and retained state

Kyle Kingsbury-inspired review perspective, not a review by Kyle Kingsbury.

**P2 — Preserve the current scroll position after a heading-link click.**
Location: `Sources/Preview/PreviewController.m:284–286`.

The fixed starred heading link navigates correctly in native WebKit.
However, immediate state capture rejects its new scroll position.
`document.baseURI` becomes `nvalt-asset://…/#release-plan`, while `capture->documentBase` remains the fragment-free document URL.
The equality check therefore returns cached offsets instead of current offsets.

The new native probe activates `[[*Release plan][Starred target]]` and immediately captures viewer state.
WebKit scrolls to **2,540 pixels**, but the captured state contains **no `scrollY` value**.
An immediate Source, viewer, or note transition can consequently restore an older position before the 200 ms timer updates its cache.

Compare document identity with only the fragment removed, while retaining the other identity and generation checks.
This shared provider code predates this PR. Ordinary Org heading links now expose the behavior.

Command: `python3 Tests/OrgPreviewReview/round2/kingsbury/run.py`.
Current result: **24 passing checks, then one failed assertion**.
The earlier **146-check run** passed native navigation for six link forms, independent window state, source replacement, and exact displayed-document export.
The final probe adds immediate state capture after every link activation.

Evidence: `Tests/OrgPreviewReview/round2/kingsbury/{probe.m,failure-output.txt,failure-metadata.json,initial-output.txt,report.md}`.
Snapshot: `4467e7a` plus the frozen heading fix, with stable hashes in the metadata.
Helper SHA-256: `dc5c563e75589ed615bc9faaad465f093ba180ac9c1b6baa3c4b2d874123fcba`.
The run used macOS 26.5.2, Xcode 26.6, and Intel code under Rosetta.

Limits: DOM-initiated link activation reaches the real WebKit navigation delegate, but the probe does not send physical mouse events.
It uses two standalone providers and a test export panel, without browser controllers, shared IME edits, or actual macOS 10.13 execution.
