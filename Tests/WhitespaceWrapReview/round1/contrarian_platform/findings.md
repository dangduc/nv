# Round 1: contrarian platform and scope

No actionable finding was found in this focused matrix for `83a7307`, compared with `f772c4b`.
The adjustment affects ordinary-space geometry in prose as well as long space runs. The evidence does not support a claim of unchanged prose geometry.

## Executed evidence

The harness extracts the exact production glyph delegate from `Sources/Editor/LinkingEditor.m:286`.
It uses native NSTextView, NSTextStorage, NSLayoutManager, and NSTextContainer objects with in-memory source.
The native baseline omits the new delegate. All other attributes and layout settings match the candidate.
No window, application process, note library, or preference domain opened.

The x86_64 run passed 12,693 assertions on macOS 26.5.2 with Xcode 26.6.
It covers 24 cases before and after a font-only attribute change.
Each view uses word wrapping, plain source mode, a 220-point container, and a fixed initial selection.

The six configurations are:

| Font at 14 points | Alignment | Writing direction |
| --- | --- | --- |
| Menlo | Left | Left to right |
| Helvetica | Left | Left to right |
| Times | Right | Left to right |
| Helvetica | Center | Left to right |
| Times | Justified | Left to right |
| Helvetica | Right | Right to left |

Each configuration contains prose, 140 trailing spaces, protected whitespace, and mixed-script source.
The protected fixture contains tabs, nonbreaking spaces, and U+2002/U+2003 spaces, with no ordinary spaces.
The mixed-script fixture contains Arabic, Hebrew, Chinese, Devanagari, decomposed accents, and joined emoji.
Native callbacks reported 12 fonts, including AppleColorEmoji, GeezaPro, PingFang, and Devanagari fallback fonts.

The font-only change replaces Menlo 14 with Times 20. All other configurations change to Menlo 20.
The harness changes only NSFontAttributeName on the existing text storage. It then requests glyphs and layout again.

## Preserved invariants

Every comparison preserves source characters, the initial selection, glyph IDs, UTF-16 indexes, and bidirectional levels.
The only glyph-property difference removes Elastic from a non-control U+0020 glyph.
All line rectangles and glyph positions remain finite.
The font-only change preserves the source, selection, and paragraph attributes.
Eligible spaces retain their adjusted flags after that change.

The protected-whitespace fixture retains identical native properties, line fragments, and glyph positions in every configuration.
This result also holds after the font-only change.
Thus the measured tab and nonbreaking-space behavior remains outside the adjustment's direct scope.

## Geometry changes from fixed-width ordinary spaces

Long space runs occupy additional visual lines in all six configurations.
Before the font change, the candidate uses seven lines at Menlo 14 and three lines at the proportional fonts.
The native baseline uses one line in each case.
After the font change, the candidate uses four lines at Times 20 or nine lines at Menlo 20. The baseline still uses one.
These line-count changes are the requested ordinary-space wrapping behavior.

Other metric changes follow from assigning ordinary spaces their font width:

- Left-aligned prose at Menlo 14 and Helvetica 14 retains identical geometry in this fixture.
- Times 14 right-aligned prose retains its line ranges, with a maximum coordinate difference of 3.5 points.
- Helvetica 14 centered prose retains its line ranges, with a maximum coordinate difference of 1.944824 points.
- Times 14 justified prose retains its line ranges, with a maximum glyph-coordinate difference of 8.098236 points.
- After the change to Menlo 20, the prose fixture uses eight candidate lines versus seven baseline lines.

The last result shows a font-size boundary where fixed space widths change ordinary prose wrapping.
It is not character wrapping or a source mutation: the native word-wrap mode, source, glyph IDs, and paragraph attributes remain intact.
The justified fixture still fills its first three line rectangles to approximately 220 points.
The change in internal glyph positions does not establish a loss of justification.

Across the matrix, geometry differs in 13 cases before the font change and 16 afterward.
A tolerance of one millionth of a point excludes insignificant floating-point differences from this count.
The report treats these as consequences of the chosen fixed-space policy, not independent correctness failures.

## Limits

The run covers one host and three requested font families, with native font substitution.
It does not establish macOS 13 behavior or correctness for every font, alignment, or writing system.
It uses full-range font changes. It does not cover every mixture of explicit font runs or paragraph attributes.
The selection checks concern preservation during layout and attribute changes, not pointer hit testing, visual caret placement, or keyboard movement.
No on-screen drawing, accessibility, printing, or timing claim follows from these measurements.

The baseline is native layout without the new delegate, not a launched baseline nvALT app.
The candidate uses the exact extracted method, not a reimplementation or the existing whitespace prototype.
The evidence is independent of the earlier synthetic buffer tests.

## Reproduction

Run this command from the worktree:

```sh
python3 Tests/WhitespaceWrapReview/round1/contrarian_platform/run.py
```

The script holds `/Users/duc/dev/nv/build/pr-review/gui.lock` during native execution.
The small report and log are `results.json` and `output.txt` beside this document.
Generated source and binaries remain under `build/WhitespaceWrapReview/round1/contrarian_platform`.
No production file, commit, or remote state changed.
