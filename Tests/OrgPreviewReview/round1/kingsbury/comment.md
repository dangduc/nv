## Preview review round 1 — asynchronous state and closure

Kyle Kingsbury-inspired review perspective, not a review by Kyle Kingsbury.

**No actionable defect found.** New executable evidence passed **79 checks** at `4467e7a7251ff3846c6d255db3bd64f465fda6b2`.

The native probe compiles the production snapshot, renderer, and preview controller with the actual Org helper and a real `WKWebView`.
A gate delays only delivery of completed production results.

- An obsolete successful Org result cannot replace a newer HTML note or its DOM.
- Two Org generations deliver in reverse order. The older result cannot replace the current note generation.
- An obsolete production error cannot hide a later successful Org document.
- A delayed export response survives provider closure and writes the exact originally displayed Org bytes.
- A new provider displays another Org note before the old callback arrives. Late completion releases the closed provider without changing its replacement.

Command: `python3 Tests/OrgPreviewReview/round1/kingsbury/run.py`.
Evidence: `Tests/OrgPreviewReview/round1/kingsbury/{probe.m,output.txt,metadata.json,report.md}`.
The run used macOS 26.5.2, Xcode 26.6, and Intel code under Rosetta.
Production input hashes remained stable during the run.

Limits: four deterministic schedules across eight requests.
The gate holds results after conversion, so this probe does not cover cancellation during helper execution or timeout cleanup.
It also does not cover shared IME edits, window restoration, or actual macOS 10.13 execution.
The export panel is a test double. Conversion, sanitization, WebKit display, and export bytes remain real.
