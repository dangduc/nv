Org source review — round 2, contrarian: correction check

All three reported findings are closed at `85a48cb17254f33a467308954713ce36746a80e2`.
Unfinished literals no longer suppress later complete literals. CRLF preserves supported multiline emphasis. Explicit Org line breaks retain the preceding emphasis capture.

I independently reran the unchanged reviewer gate with `--assert-semantic --output-prefix verified-`.
It passed all 23 semantic fixtures with zero mismatches, 377 mechanical checks, and 38 edited-link checks.
The original run had nine semantic mismatches.

I also reran `python3 Tests/OrgSource/run.py`: all 864 checks and dependency/query hashes passed.
Closed outer literals, UTF-16 ranges, indented CRLF continuation, and comment, heading, and list barriers remain covered.
The correction uses linear passes, the existing cancellation/deadline checks, and at most 2 MiB for the additional offset table.

Evidence: `Tests/OrgSourceReview/round2/contrarian/fix-validation.md`, `verified-*`, and `maintained-output.txt`.
The checks used macOS 26.5.2 and Xcode 26.6 with Intel code through Rosetta.
They do not establish final app pixels or macOS 10.13 runtime behavior.
This was a targeted correction check, with no production edits or additional review round.
