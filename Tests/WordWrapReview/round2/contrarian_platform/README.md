# Round 2: platform and Unicode review

No new actionable finding emerged at commit `4c8f6b449504a50caa460d78efebd42b94beaba6`.
Both arm64 and x86_64 passed 1,764 assertions on macOS 26.5.2 (25F84), with Xcode 26.6 (17F113).
The Intel run used Rosetta.

The runner compiles the corrected production typesetter and extracts the production space delegate.
It first compares both source files and the typesetter header against the reviewed commit.
The adjacent `results.json` records production hashes, probe hashes, and per-architecture evidence.
The probe creates no windows and changes no notes, preferences, or production files.

## Hypothesis 1: cleanup loses Unicode state between layout calls

Twelve cases combine two widths with six separators: LF, CRLF, CR, NEL, LINE SEPARATOR, and PARAGRAPH SEPARATOR.
The sources contain combining accents, joined emoji, Indic clusters, Hebrew, Arabic, and ordinary prose.
Each source has 384 or 387 UTF-16 code units.

The probe calls the public native typesetter entry point with a requested limit of two line fragments.
It resumes at the returned glyph index until the source completes.
Every case uses three calls, for 24 resumed calls per architecture.
Each return makes forward progress and preserves a composed-character boundary.

The completed layout matches a fresh production text system.
The comparison includes line ranges, rectangles, glyph positions, glyph IDs, properties, UTF-16 indexes, and bidi levels.
Native character layout also preserves the same UTF-16 indexes, bidi levels, and normalized storage attributes.

The native engine did not restrict these calls to two visual lines.
This evidence does not establish interruption inside an unfinished paragraph or exhaustion of a text container.

## Hypothesis 2: empty source retains stale font or paragraph state

Two layout managers share one text storage and use different widths.
Twenty observation phases cover initial layout and three cycles through an empty source.
Each cycle installs different Unicode text and a different font after the empty state.
It then replaces a complete composed sequence, changes the storage font, and resizes one container.

The fonts are Menlo, Times New Roman Italic, and Cochin.
The replacement sources contain CRLF, CR, NEL, LINE SEPARATOR, PARAGRAPH SEPARATOR, and NBSP.
Both layout managers match fresh layout after each observed transition.
The source characters remain exact, and storage attributes match native font normalization.
Both empty layouts contain zero glyphs.

Across both hypotheses, each architecture records 144 paragraph completions with active analysis before cleanup.
Every observed completion releases that analysis, and all observed paragraph starts have matching ends.
The observer records 448 narrowed lines, so the fixtures exercise the production correction.

## Limits and reproduction

The probe does not inspect visible rendering, caret movement, input methods, accessibility, or the application event loop.
It does not establish runtime compatibility with older macOS versions or arbitrary fonts and paragraph styles.
The previously documented geometry and performance limits remain outside this review.

Run both architectures on Apple Silicon:

```sh
python3 Tests/WordWrapReview/round2/contrarian_platform/run.py
```

Use `--arch arm64` or `--arch x86_64` to select one architecture.
Each process has a 45-second timeout.
Generated headers, binaries, and detailed output remain in `build/WordWrapReview/round2/contrarian_platform/`.
