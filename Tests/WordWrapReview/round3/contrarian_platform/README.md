# Round 3: platform and Unicode review

No new actionable finding emerged at commit `63911bf2c66d438f178b43a8b9e996787e29acc9`.
Both arm64 and x86_64 passed 660 assertions on macOS 26.5.2 (25F84), with Xcode 26.6 (17F113).
The Intel run used Rosetta.

The runner compiles the production typesetter and extracts the production space delegate.
It first compares both source files and the typesetter header against the reviewed commit.
The evidence records production and probe hashes.
The probe uses native NSTextView instances without windows.
It changes no notes, preferences, production files, or earlier review artifacts.

## Hypothesis 1: edits inside Unicode sequences corrupt layout at wraps

Three focused fixtures start with a combining base letter, a heart, and a woman emoji.
Each initial target starts at an actual line boundary in a 104-point container.
The initial font is Menlo 18, with native fallback fonts.

The native edit sequence contains these operations:

- The combining fixture adds and replaces accents, adds a second mark, and removes a mark. It ends with one precomposed character.
- The presentation fixture adds FE0E, replaces it with FE0F, removes it, and adds it again.
- The emoji fixture adds and replaces a skin-tone modifier. It adds a joiner and laptop, removes the joiner, and restores it.

Each fixture also ends with native deletion of the complete target.
The candidate and native control receive the same explicit replacement ranges and deletion commands.
Together, they perform 34 native edit calls per architecture.
Every edit produces the exact requested source characters in both controls.
Their selections remain equal and in bounds.

Every observed line starts at a composed-character boundary.
The candidate matches native character layout for UTF-16 glyph indexes, bidi levels, and storage attributes after font normalization.

## Hypothesis 2: later width or font changes reuse stale measurements

After the sequence edits, each fixture changes its container width from 104 to 76 points.
It then changes the font to Helvetica 22 and the width to 137 points.
Each observed phase compares the live candidate with a fresh production text system.
Line ranges, rectangles, glyph positions, glyph IDs, properties, UTF-16 indexes, and bidi levels match exactly.

Each architecture completes 26 observation phases.
The target position starts a line in 18 phases.
The observer records 44 narrowed lines, so the fixtures exercise the production correction.

## Limits and reproduction

These are direct native text commands, with explicit replacement ranges.
They do not cover physical keyboard events, marked-text composition, input methods, accessibility, visible rendering, or the complete application event loop.
The three focused strings do not establish correctness for every Unicode sequence, font, or paragraph style.
The runs do not establish runtime compatibility with older macOS versions.
The previously documented geometry and performance limits remain outside this review.

Run both architectures on Apple Silicon:

```sh
python3 Tests/WordWrapReview/round3/contrarian_platform/run.py
```

Use `--arch arm64` or `--arch x86_64` to select one architecture.
Each process has a 45-second timeout.
Generated headers, binaries, and detailed output remain in `build/WordWrapReview/round3/contrarian_platform/`.
The adjacent `results.json` records the result and source hashes.
