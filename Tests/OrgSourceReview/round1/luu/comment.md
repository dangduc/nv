### Round 1 — Dan Luu-inspired performance review

**[P2] Cache the line boundary during Org link decoration.**

At `Sources/Editor/AttributedPlainText.m:245` in `decc678`, the loop calls `lineRangeForRange:` again for every Org link on the same line.
`LinkingEditor` calls this method synchronously during text edits, outside the background parser budget.
The independent probe measured one-character refreshes of 40 / 146 / 561 / 2,199 ms for 1,000 / 2,000 / 4,000 / 8,000 links.
The largest fixture contains 248,000 UTF-16 units.
An experiment that caches each line end reduces the 8,000-link refresh to 72 ms, with identical source characters, labels, target URLs, and link counts.

Cache the line boundary until the cursor reaches the next line. Add a deterministic work-count regression for a dense paragraph.

Evidence: `Tests/OrgSourceReview/round1/luu/` contains the executable probes, source hashes, full measurements, and report.
The parser probe also passes 78,405 bounds, capture-count, and fallback-recovery checks. It finds no additional actionable defect.
These are isolated method measurements on macOS 26.5.2, with Intel code under Rosetta. They exclude window layout and total typing latency.

**Resolution:** The production loop now caches each line end. The maintained link suite passes 2,060 checks, including a deterministic work-count regression.
That regression rejects the original commit with the expected failure.
The fixed production 8,000-link refresh has a 79 ms median, with all expected links intact.
The original and final source hashes and measurements remain in the evidence directory.

This review uses the requested perspective and does not represent Dan Luu's review or endorsement.
