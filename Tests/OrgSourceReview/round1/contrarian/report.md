# Org source review — round 1, contrarian

This review challenges the source semantics for ordinary note content.
It found one actionable error.

## P2: Distinguish hashtag prose from Org comments

The production parser colors `#travel *book tickets*` as one comment.
It also suppresses the emphasis capture for `*book tickets*`.
The same error occurs after a blank line, after a comment, and with leading spaces.
These are ordinary prose lines in Org.
Org comments require whitespace after `#`, as described in the [Org manual](https://orgmode.org/manual/Comment-Lines.html).

The error depends on the preceding content.
With `#+TITLE: Trip` immediately before the same hashtag line, the parser returns the expected emphasis capture and no comment capture.
Thus, an unrelated title directive changes the colors of unchanged note text.

`Resources/Syntax/org.scm:6` accepts every grammar `comment` node as a comment capture.
`Sources/Editor/NVSourceHighlighter.m:169–171` then excludes each such node from the supplemental analysis.
The pinned grammar accepts a non-whitespace character after `#` and can combine consecutive lines into one comment node.
The later prefix check at lines 228–231 only handles eligible prose, so it cannot correct these false comment nodes.

A fix needs to apply the ordinary Org prefix rule to grammar comment nodes, including each line in a combined node.
False comment lines need prose analysis, and their broad comment captures need removal.
Actual comments and literal block contents must retain their current protections.

## Executed evidence

Run the evidence generator from the repository root:

```sh
python3 Tests/OrgSourceReview/round1/contrarian/run.py
```

The runner compiles the unchanged production highlighter, grammar wrappers, and runtime.
It also compiles the unchanged production link methods into a native Cocoa probe.
The fixtures use short, ordinary note content.
The runner does not alter production code.

The parser probe recorded 18 fixtures, four semantic mismatches, and 31 successful capture-bounds checks.
All four mismatches concern hashtag prose.
The remaining fixtures cover comments, TODO/DONE boundaries, prose, Unicode, literals, and source/example blocks.
The probe also records the documented emphasis exclusions for quote and verse blocks.
These exclusions are scope limits, not additional findings in this review.

The link probe passed 20 checks.
It covers explicit HTTP/HTTPS targets, Unicode labels, unresolved targets, source preservation, and a newline insertion within a label.
The newline check uses the complete former line, as supplied by the production editor.
This avoids attributing an error to a partial range that the editor does not supply.

The runner supports a regression gate:

```sh
python3 Tests/OrgSourceReview/round1/contrarian/run.py --assert-semantic --output-prefix fixed-
```

This gate exits unsuccessfully until all semantic fixture expectations match the result.
The output prefix keeps the original evidence files intact.
The gate returned exit status 1 before a fix, with the same four semantic mismatches.

Evidence files:

- [Parser fixture output](parser-output.txt)
- [Link output](link-output.txt)
- [Host, commit, and source hashes](metadata.json)
- [Parser probe](parser-probe.m)
- [Link probe](link-probe.m)
- [Runner](run.py)

## Scope and limits

The host was macOS 26.5.2 with Xcode 26.6.
The native probes targeted x86_64 and macOS 10.13, and ran through Rosetta.
This review did not run on macOS 10.13 or capture the visible editor colors.
The capture kinds determine the color categories, but the probe did not measure the final pixels.

The review inspected import and metadata choices without another archive or app integration run.
It found no additional actionable error in those paths.
It did not assess full Org conformance, custom TODO settings, agenda behavior, or embedded language analysis.
