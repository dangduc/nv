### Round 2 — Dan Luu-inspired performance review

No new actionable finding. This is a review perspective, not a review or endorsement by Dan Luu.
Reviewed helper: 366,408 bytes, SHA-256 `dc5c563e75589ed615bc9faaad465f093ba180ac9c1b6baa3c4b2d874123fcba`.

I wrote new fixtures and an independent heading/link oracle for the fix:

- All 483,229 assertions pass for intended fragment targets, unique anchors, duplicate IDs, Unicode IDs, and content boundaries.
- On identical journals with 1,024 headings and 8,192 links, helper median time changes from 56.128 to 63.091 ms.
- On 64 headings with 16,384 links, it changes from 52.565 to 64.069 ms.
- The largest helper RSS observation is 21,139,456 bytes, versus 20,946,944 bytes for the original helper on these fixtures.
- The actual renderer passes 30 additional checks. Cancellation followed by a newer snapshot yields one callback per request and no stale link labels.
- The replacement and old-child cleanup finish within 49.380 ms after cancellation.

Evidence: `Tests/OrgPreviewReview/round2/luu/`, including the code, all measurements, source hashes, and `report.md`.
The comparison uses three trials per helper and alternates execution order.
It measures the whole fix, including larger HTML output, rather than isolated index operations.

These results cover Intel code through Rosetta on macOS 26.5.2 / Xcode 26.6.
They exclude WebKit display and application debounce, and do not establish costs at the full input limit.
