Org source review — round 2, contrarian

Reviewed `4dab02a9020ff8f76cceeffc75a001927255a17e` against `f3a8abb2b7942d06ec33af64b4946cfd1b6db163`.
The first-round hashtag correction is present.

Three findings remain:

1. **P2: Unfinished literals suppress later complete literals.** `Draft =token then ~code~.` loses the `~code~` capture. The reverse delimiter combination also fails. `NVOrgCaptures` stores one pending opener for both delimiter types (`Sources/Editor/NVSourceHighlighter.m:239–255`). Five fixtures expose this error. Complete outer literals must still suppress inner markup.
2. **P2: CRLF breaks supported multiline emphasis.** The strong and code captures in two-line fixtures disappear with CRLF but pass with LF. The grammar splits CRLF into two breaks. Its paragraph excludes the LF, so the supplemental pass resets its pending markup (`NVSourceHighlighter.m:242,265`). Org import preserves these line endings. Source analysis needs consistent logical newline handling without changing stored text or UTF-16 ranges.
3. **P3: Markup before an explicit line break loses its color.** `*word*` or `~code~` followed by two backslashes and a newline loses its capture. `NVOrgClosingBoundary` omits the valid backslash boundary (`NVSourceHighlighter.m:166–167`).

The [Org syntax specification](https://orgmode.org/worg/org-syntax.html) supports the paired delimiter, plain-text fallback, and closing-boundary expectations.

I wrote and ran native probes against unchanged production code. The result was 23 semantic fixtures with nine mismatches across these findings. All 329 mechanical checks and 38 Unicode edited-link checks passed.

Command: `python3 Tests/OrgSourceReview/round2/contrarian/run.py --assert-semantic` (exit 1 for the reported mismatches).

Evidence: `Tests/OrgSourceReview/round2/contrarian/{report.md,parser-probe.m,tree-probe.m,link-probe.m,parser-output.txt,tree-output.txt,link-output.txt,metadata.json}`.

The probes ran on macOS 26.5.2 with Xcode 26.6, using Intel code through Rosetta. They did not inspect final display pixels or keyboard focus. The link checks exercise whole-note refresh, not LinkingEditor's partial edit range calculation. No production code changed during this review.
