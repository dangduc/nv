# Org source review — round 2, contrarian

This review challenges the treatment of ordinary unfinished source text and imported line endings.
The reviewed commit is `4dab02a9020ff8f76cceeffc75a001927255a17e`, against base `f3a8abb2b7942d06ec33af64b4946cfd1b6db163`.
The previous round's hashtag comment correction is present.

1. **P2: An unfinished literal hides a later valid literal.**

   `Draft =token then ~code~.` has no capture for `~code~`.
   The reverse case, `Draft ~token then =literal=.`, also loses the complete literal.
   Removing the unfinished opener restores the capture.
   Five fixtures expose this error, including Unicode text and a single intervening newline.

   `NVOrgCaptures` keeps one pending opener for both literal types at `Sources/Editor/NVSourceHighlighter.m:239`.
   Until that opener closes, the pass cannot recognize another delimiter type.
   An unfinished literal is plain text, so it cannot suppress a later complete literal.
   The [Org syntax specification](https://orgmode.org/worg/org-syntax.html) defines matched delimiters and the fallback to plain text.

   The fix needs to recognize a complete later literal after an unmatched opener.
   A complete outer literal must still suppress inner markup.
   The latter behavior already passes the control fixtures.

2. **P2: CRLF source loses supported multiline emphasis.**

   `Review *first\r\nsecond* today.\r\n` has no strong capture.
   The corresponding LF fixture has the expected capture.
   The same difference affects a code literal with one newline.
   These are supported source forms with different line endings.

   The direct grammar probe explains the difference.
   For CRLF, the grammar ends a paragraph at the carriage return and places the line feed outside that paragraph.
   The supplemental pass then resets its pending markup at the ineligible line feed (`Sources/Editor/NVSourceHighlighter.m:242` and `:265`).
   For LF, one paragraph contains both lines.

   The integration fixture explicitly checks that Org import preserves CRLF source characters and bytes (`Tests/OrgSource/Integration/probe.inc:32`).
   Thus, import does not remove this input before source analysis.
   The fix needs to treat CRLF as one logical newline without changing the stored note text or UTF-16 capture ranges.

3. **P3: Explicit Org line breaks remove the preceding emphasis color.**

   `*word*` immediately followed by two backslashes and a newline has no strong capture.
   The equivalent code literal also loses its capture.
   `NVOrgClosingBoundary` omits backslash at `Sources/Editor/NVSourceHighlighter.m:166`.
   The [Org syntax specification](https://orgmode.org/worg/org-syntax.html) includes backslash as a valid closing boundary.
   The fix needs to accept that boundary for emphasis and literal text.

The independent runner compiled the unchanged production parser, highlighter, grammar wrappers, runtime, and source link methods.
It recorded 23 semantic fixtures with nine mismatches across these three findings.
It passed 329 mechanical checks for source preservation, UTF-16 ranges, Unicode boundaries, and fresh versus incremental capture equivalence.
The link probe passed 38 checks for edited destinations, Unicode labels, CRLF, incomplete delimiters, unresolved targets, and unrelated background attributes.

Run the review gate from the repository root:

```sh
python3 Tests/OrgSourceReview/round2/contrarian/run.py --assert-semantic
```

The gate returned exit status 1 because the nine expected captures were absent.
The plain runner records mismatches without an unsuccessful exit status.
The `--output-prefix fixed-` option preserves the original output during a later correction check.

The [metadata](metadata.json) records the source hashes, macOS 26.5.2, Xcode 26.6, and Intel execution through Rosetta.
The build targets macOS 10.13, but this review did not run on that system.
The [parser output](parser-output.txt), [grammar output](tree-output.txt), and [link output](link-output.txt) preserve the executed evidence.

This review did not inspect final display pixels, physical keyboard focus, or Undo behavior in an app window.
The link probe uses the whole-note decoration API and does not claim to exercise LinkingEditor's partial edit ranges.
The fixture expectations cover the stated subset, not full Org conformance or custom Emacs settings.
The review did not alter production code or reproduce a scanner vulnerability.
