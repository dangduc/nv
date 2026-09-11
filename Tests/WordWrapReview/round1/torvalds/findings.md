# Round 1 findings

No actionable shipping finding was verified within this review scope.
The source-style assertions passed on arm64 and x86_64.
The previous character layout failed the fitting-word condition in 36 source-style cases.

## Evidence

The review ran on macOS 26.5.2 (25F84), with Xcode 26.6 (17F113).
The x86_64 process ran under Rosetta on the same host.
Both runs used the frozen production commit `4b049709b2cecc6eac80514586ccacc119d12802`.

| Result | arm64 | x86_64 |
| --- | ---: | ---: |
| Matrix cases | 315 | 315 |
| Glyph comparisons on identical line ranges | 9,525 | 9,525 |
| Source-style geometry differences | 0 | 0 |
| Source-style split words | 0 | 0 |
| Extended-style geometry differences | 85 | 85 |
| Extended-style split-word records | 45 | 45 |

The source characters remained unchanged in every candidate and reference snapshot.
The extended-style differences appear in the following bounded observations.
They are not shipping findings because this review did not establish a source-app path to those paragraph attributes.

## Bounded paragraph observations

### Positive tail indent does not preserve all fitting words

Production location: `Sources/Editor/NVSourceTypesetter.m:106`.

Use Menlo 18, container width 160, padding 5, natural alignment, and `tailIndent=130`.
Use `alpha beta gamma delta epsilon zeta eta theta` as the source.
The production layout ends consecutive lines with `epsilon ze` and `ta eta the`.
The words `zeta` and `theta` fit the 120-point content width but split.
The native word layout keeps these words whole.

Line 40 treats a positive tail indent as an absolute boundary.
Line 106 narrows the fragment width without changing that absolute boundary.
The temporary width therefore cannot reliably select the intended word break.

The previous character layout also splits fitting words for this fixture.
This observation is an incomplete refinement of an existing behavior, rather than a verified new source-app regression.
The common source style has zero indents at `Sources/Preferences/GlobalPrefs.m:566`.
The source session installs that style at `Sources/Editor/NVNoteEditingSession.m:137` and `:293`.
No inspected source action creates a positive tail indent.

### Natural alignment with explicit RTL direction keeps the temporary horizontal shift

Production location: `Sources/Editor/NVSourceTypesetter.m:108`.

Use Menlo 18, width 160, natural alignment, and explicit right-to-left paragraph direction.
Use `שלום עולם שלום עולם שלום עולם שלום עולם` as the source.
The first line has the same character range under both layouts.
Every glyph appears 36.511 points left of its native word-layout position.
The code restores shifts for explicit right and center alignment only.

The native-action probe uses `NSTextView` with `richText=NO`, as the source editor does.
Its `makeBaseWritingDirectionRightToLeft:` action sets explicit right alignment, not natural alignment.
That reachable style passes the source-style geometry checks.
The attribute combination necessary for this observation has no verified source-app path.

### Justification uses the temporary narrow width

Production location: `Sources/Editor/NVSourceTypesetter.m:113`.

Use Menlo 18, width 160, justified alignment, and the Latin fixture from the first observation.
Both layouts put `alpha beta ` on the first line.
The production used rectangle is 134.625 points wide, while native word layout uses 160 points.
Restoring the fragment rectangle cannot restore the glyph advances that justification already computed.

The plain-text native-action probe ignores `alignJustified:`.
No inspected nvALT source action supplies justified paragraph attributes.
This observation remains outside the verified source path.

## Source and API review

The character accesses at lines 58 and 90 follow checks against the current storage and paragraph ranges.
The paragraph-length check limits conversions to `CFIndex`.
The fit and token checks bound the later range additions within that paragraph.
The binary search also guards access to the preceding boundary.
No source-level out-of-bounds path was found under the documented Cocoa callbacks.

The Core Text references and the boundary buffer have matching releases at paragraph replacement and object destruction.
`beginParagraph` clears each cached paragraph snapshot before the next paragraph layout.
Each editor installs its own typesetter in `Sources/Editor/LinkingEditor.m:64`.
The production implementation appears in the Xcode Sources build phase.

The API review used the installed Xcode SDK declarations for `NSTypesetter`, `NSATSTypesetter`, and `CTTypesetter`.
The probe does not establish behavior on macOS 10.13 or macOS 13.7.8.
It also does not establish correctness for arbitrary attributed text, exclusion paths, vertical layout, or mixed temporary font attributes.
