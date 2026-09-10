# Round-two delimiter corrections

The fixes address three findings against `4dab02a9020ff8f76cceeffc75a001927255a17e`.
They change the supplemental Org pass in `NVSourceHighlighter.m`. The vendored grammar and stored source remain unchanged.

The literal pass finds valid closing delimiters in reverse order, then selects complete spans from left to right.
An unmatched opener stays plain. A complete outer literal still suppresses inner markup.
This also permits a later literal after a delimiter that began inside an earlier complete span.

The grammar places some CRLF line feeds outside paragraph nodes.
The supplemental pass connects these gaps only between eligible prose lines, including their indentation.
Comments, headings, list markers, and other protected boundaries still stop a span.
CRLF counts as one logical newline. Captures retain the original UTF-16 ranges, including both characters.

Backslash is now a valid closing boundary, as specified in [Org text markup syntax](https://orgmode.org/worg/org-syntax.html).
Thus, an explicit Org line break does not remove the preceding emphasis or literal capture.

Every added pass is linear in source length and checks the existing cancellation token and deadline.
The closing-offset table uses four bytes per UTF-16 unit, at most 2 MiB under the existing source limit.
Capture and display limits remain unchanged.

Validation on the corrected working tree:

- `python3 Tests/OrgSource/run.py`: 864 checks passed, plus dependency and query hashes.
- The unchanged round-two contrarian gate: 23 semantic fixtures, zero mismatches, 377 mechanical checks, and 38 link checks.
- Three negative controls failed at the intended maintained fixture: the previous unmatched-opener implementation, removed CRLF adaptation, and removed backslash boundary.

The maintained fixtures include Unicode, indented CRLF continuation, two-newline rejection, comment/heading/list barriers, empty delimiters, and closed-literal precedence.
They compare fresh and incremental captures and check that analysis preserves the original source.

The review gate ran with `--assert-semantic --output-prefix fixed-`.
Original failing evidence remains in `Tests/OrgSourceReview/round2/contrarian/`; the `fixed-*` files record the correction.
Native test logs are in `build/org-source-r2-fix-tests.log` and `build/org-source-r2-contrarian-fixed.log`.
Negative-control logs are in `build/org-source-r2-negative-controls/`.

These are native source-analysis checks. They do not establish final app rendering, old-macOS execution, or complete Org conformance.
