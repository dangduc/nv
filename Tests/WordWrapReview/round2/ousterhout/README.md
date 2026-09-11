# Round 2: Ousterhout-inspired review

No new actionable finding.
The paragraph-completion cleanup fixes the observed retention without disrupting the tested partial-layout continuation paths.
This review uses engineering priorities inspired by John Ousterhout. It does not represent his authorship or endorsement.

Reviewed revision: `4c8f6b449504a50caa460d78efebd42b94beaba6`.
The review targets `NVSourceTypesetter.m:7–27`, including cleanup after native `endParagraph`.

## Executed evidence

The probe links the current production class and imports the prior headless harness explicitly.
The round-one entry point is renamed and never called.
New observer methods forward production callbacks unchanged during the positive run.
No windows, application preferences, or personal notes are accessed.

Three hypotheses were tested:

1. Cleanup must remain safe when a text container ends before its paragraph ends.
2. The same typesetter must remain reusable across blank paragraphs, CRLF separators, and font changes.
3. The completion assertion must fail when only the new cleanup call is omitted.

Both arm64 and x86_64 pass 230 checks.
Each architecture observes 156 paragraph-completion callbacks, including 78 callbacks with an active measurement beforehand.
Six callbacks end inside an unfinished source paragraph because the available container is exhausted.
All completed callbacks return with both analysis fields cleared.

The finite-container fixture initially provides only a 240-by-45-point container.
Its first paragraph contains between 1,177 and 1,232 characters.
The first observed completion ends after 36 glyphs while the paragraph range remains `{0, 1177}`.
The test adds further containers only after that partial layout returns.
The resumed layout then matches a fresh production layout across all containers.
Source attributes remain unchanged.

Six text systems also undergo 24 reuse cycles.
The replacements alternate blank lines with text containing CRLF and blank paragraphs.
Font and alignment attributes change during those replacements.
The resulting line ranges, rectangles, and used rectangles match fresh layouts.
Both caches are empty afterward, and all 72 created typesetter instances are destroyed.

The negative control suppresses `clearParagraphAnalysis` only while the production `endParagraph` call is active.
It retains defensive cleanup during `beginParagraph` and destruction.
Both architectures reject that omission at the first completion assertion.
This demonstrates that the check detects the specific missing cleanup rather than merely exercising layout.

## Reproduce

```sh
python3 Tests/WordWrapReview/round2/ousterhout/run.py
```

Host: macOS 26.5.2 (25F84).
The runner targets macOS 11 for arm64 and 10.13 for x86_64; the Intel process runs through Rosetta.
`results.json` records the reviewed revision, production-file hash, callback counts, and negative-control failure.
Generated binaries and logs are under `build/WordWrapReview/round2/ousterhout/`.

## Limits

This review covers headless native layout, not the app's window lifecycle or physical input events.
Finite sequential containers exercise a stronger partial-completion case than the app's ordinary single editor container.
The test compares line geometry and source attributes; it does not inspect every painted glyph or measure heap memory.
It does not establish all AppKit callback orders or behavior on macOS 13.
The first prototype provided all containers up front, which let AppKit complete the paragraph during the initial layout request.
The final probe adds later containers afterward and verifies that actual partial-completion callbacks occurred.
