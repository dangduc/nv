# Independent check of the round-two corrections

All three findings from the second contrarian source review are closed at `85a48cb17254f33a467308954713ce36746a80e2`.
This check covers the reported corrections and their adjacent regression cases.
It does not constitute another review round.

I reran the unchanged review gate:

```sh
python3 Tests/OrgSourceReview/round2/contrarian/run.py --assert-semantic --output-prefix verified-
```

The command returned exit status 0.
All 23 semantic fixtures matched their expected captures, compared with nine mismatches before the correction.
The probe passed 377 mechanical checks and 38 Unicode edited-link checks.
The [metadata](verified-metadata.json) records the corrected commit and production source hashes.
The highlighter hash matches the author's `fixed-*` run.

The complete later literal now receives its capture after an unfinished opener of the other delimiter type.
The Unicode and single-newline variants also pass.
Complete outer literals still suppress inner markup.
The fixture outputs retain both the original failure and the corrected result.

CRLF and LF fixtures now produce the same expected multiline emphasis categories.
Captures retain both characters of the CRLF and the original UTF-16 extent.
The CRLF fixture with two newlines remains outside the supported one-newline span.
The preceding strong or literal capture also survives an explicit Org line break.

I also reran the maintained source suite:

```sh
python3 Tests/OrgSource/run.py
```

All 864 checks passed, together with the dependency and query hashes.
These fixtures include closed outer literals, empty delimiters, indented CRLF continuation, and comment, heading, and list barriers.
They also cover source preservation, Unicode ranges, cancellation, and the existing large-note fallback.
The [maintained output](maintained-output.txt) preserves this run.
All reviewed production hashes remained unchanged after both commands.

The implementation still bounds work by source length.
The reverse delimiter pass performs constant work for each UTF-16 unit.
The forward pass selects disjoint literal spans and skips their contents.
The CRLF pass inspects each indentation run once, apart from the enclosing linear scan.
Every added loop checks the existing deadline and cancellation token.
The additional offset table uses at most 2 MiB under the existing source limit.
The capture and display limits remain unchanged.

The author also recorded three negative controls that fail after each corresponding correction is removed.
I inspected those logs but did not rerun or claim authorship of the negative controls.

The checks ran on macOS 26.5.2 with Xcode 26.6, using Intel code through Rosetta.
They do not establish final app pixels, old-macOS behavior, or complete Org conformance.
No production files changed during this independent check.
