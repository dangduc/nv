### Round 1 — Dan Luu-inspired performance review

Reviewed commit: `4467e7a7251ff3846c6d255db3bd64f465fda6b2`. No actionable performance finding.
This is a review perspective, not a review or endorsement by Dan Luu.

I wrote and ran independent probes against the bundled helper and unchanged production renderer:

- A representative 1,019,271-byte Org journal converts in a median 128.201 ms. The helper peak RSS reaches 36,413,440 bytes.
- The complete renderer callback takes a median 285.965 ms, including sanitization. The renderer process peak RSS reaches 59,252,736 bytes.
- Main-thread snapshot construction and queue submission take at most 0.493 and 0.186 ms for the ordinary fixtures. The main run-loop timer continues during conversion.
- Cancellation of an observed active converter produces one error callback after 0.324 ms. The operation and child process finish within 34.149 ms.
- The 50 ms converter deadline returns its timeout error after 84.195 ms. An input one byte beyond 16 MiB receives the input-limit error.

All nine helper conversions preserve the expected content. The actual renderer passes 75 focused checks.
Evidence: `Tests/OrgPreviewReview/round1/luu/`, including reproducible code, output, source hashes, and `report.md`.

These measurements cover Intel code through Rosetta on macOS 26.5.2 / Xcode 26.6.
They exclude WebKit display and application debounce, and do not establish an RSS ceiling for notes at the full input limit.
