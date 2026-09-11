# Round 1: platform and Unicode review

No new actionable finding emerged at commit `4b049709b2cecc6eac80514586ccacc119d12802`.
The three bounded experiments passed on arm64 and x86_64 through Rosetta.
The host used macOS 26.5.2 (25F84) and Xcode 26.6 (17F113).

The runner compiles the production `NVSourceTypesetter.m` and extracts the production space delegate from `LinkingEditor.m`.
It first compares these files and the typesetter header against the reviewed commit.
The evidence records SHA-256 hashes.
The probe uses windowless Cocoa text systems and creates no application window.
It changes no notes, preferences, or production files.

## Hypotheses and results

| Hypothesis | Executed evidence per architecture | Result |
| --- | --- | --- |
| Core Text measurement can split composed characters or damage native mappings. | 320 combinations of eight fonts, five widths, and eight Unicode strings. | No cluster splits. UTF-16 glyph indexes, bidi levels, and normalized storage attributes match native character layout. |
| Font metrics or separators can make a fitting token split. | 1,953 comparisons against native word layout, from 651 fitting token configurations. | No candidate token splits when native word layout keeps the token whole. |
| Cached measurements can become stale after font, color, or source changes. | 99 phases across three widths, with font changes, temporary colors, insertion, deletion, and resize. | Each live layout matches a fresh production text system. Temporary colors preserve layout geometry. |

The Unicode strings include combining accents, joined emoji, flags, keycaps, Indic clusters, Hebrew, Arabic, ligatures, and soft hyphens.
Separator fixtures include ordinary spaces, tabs, NBSP, narrow NBSP, word joiners, nonbreaking hyphens, and Unicode spaces.
The fonts are Menlo, Helvetica, Times New Roman Italic, Baskerville, Cochin, American Typewriter, Herculanum, and Zapfino.
Every requested font exists on the test host.

The token experiment first lays out each token alone with native character wrapping.
Only tokens that occupy one line enter the comparison.
It then adds three prefixes, including a tab prefix, and compares the production layout against native word wrapping.
The paragraph settings include default tab stops and tab intervals of 40 and 73 points.
Both native controls retain the production space delegate.

The live experiment compares line ranges, rectangles, glyph positions, glyph IDs, properties, UTF-16 indexes, and bidi levels with fresh layout.
Color changes use temporary foreground and background attributes, as source decoration does.
Font changes use storage attributes and exercise native fallback normalization.

Each architecture passed 9,845 assertions across the three experiments.
The observer recorded 2,834 calls that narrowed a line, so the fixtures exercised the production correction.
The negative control removes only the custom typesetter.
It found 555 fitting-token splits per architecture, which demonstrates comparison sensitivity.

## Limits

The probe does not establish runtime compatibility with macOS 10.13 or 13.7.8.
The Intel build uses a 10.13 deployment target but runs on the current host through Rosetta.
The arm64 build uses an 11.0 deployment target.

The probe does not inspect visible text, caret drawing, accessibility, input methods, or the complete application event loop.
It does not establish geometry equivalence across every wrapping policy.
Post-layout glyph shapes or properties differ from native character wrapping in 12 Unicode cases per architecture.
Those cases contain ligatures or soft hyphens, and the probe records them without a visual correctness claim.
All their composed boundaries and UTF-16 mappings pass the stated checks.

The experiments cover the listed fonts, settings, and bounded strings.
They do not establish correctness for arbitrary font features, explicit kerning, custom tab alignments, or every paragraph style.

## Reproduction

Run both architectures on Apple Silicon:

```sh
python3 Tests/WordWrapReview/round1/contrarian_platform/run.py
python3 Tests/WordWrapReview/round1/contrarian_platform/run.py --negative-control
```

Use `--arch arm64` or `--arch x86_64` to select one architecture.
Each native process has a 45-second timeout.
Generated headers, executables, logs, and detailed JSON remain in `build/WordWrapReview/round1/contrarian_platform/`.
The adjacent `results.json` contains the concise result and source hashes.
