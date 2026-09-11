# Round 2: correctness and complexity

No actionable findings in frozen commit `2ea92180939a3e51df8fe867ad548140ed455868`, compared with `75d6f42`.
This review uses a Torvalds-inspired engineering perspective.

The runner extracts the complete frozen glyph callback into a native Cocoa delegate without rewriting its body.
The callback SHA-256 is `7041b11075a6a8d51fdac388718b4a0c7bd67cb25c45d4a34cd555f562f03da4`.

Two hypotheses were checked:

1. Editing a space's neighbor leaves stale glyph properties or changes native source mappings.
2. Whitespace, supplementary scalars, or composed sequences cause incorrect classification or unsafe UTF-16 indexing.

Each architecture passed **6,703 checks**, covering **86 scalar-neighbor cases** and **258 edit phases**.
The runner used macOS 26.5.2, build 25F84, and Xcode 26.6, build 17F113.
Both arm64 and x86_64 produced identical observations.

The probe enumerates all valid Unicode scalars to find Foundation's 26 whitespace/newline members.
Each member replaces the left and right neighbor of `L R`, followed by restoration.
Every phase compares cached production glyphs with fresh production glyphs and a native layout manager without the delegate.
Glyph IDs, UTF-16 mappings, bidi levels, glyph counts, source text, and attributes match the native baseline.
Only removal of the native Elastic bit is permitted.
All 258 target spaces started with native elasticity.

Foundation includes U+200B in its whitespace set on this host.
Adjacent ASCII spaces therefore lose elasticity at `Sources/Editor/LinkingEditor.m:313`–`314`.
Other selected formatting characters retain native spacing, including U+200C, U+2060, U+FEFF, bidi controls, and U+0600.
These observations follow Foundation classification and do not imply equivalent visual behavior for those characters.

An acute mark, VS16, ZWJ, or supplementary variation selector U+E0100 after the space extends its composed range.
The guard at `Sources/Editor/LinkingEditor.m:315` preserves literal space width in each case.
The same scalars before the space, and emoji U+1F600 on either side, leave its native elasticity intact.
An initial fixture assumption grouped ZWNJ with ZWJ.
Foundation returned a singleton space before ZWNJ, so the final probe records that case as a platform observation.

Any proposed shortcut must retain the composed-range query for non-ASCII neighbors.
These results do not validate a new printable-ASCII shortcut or replace measurements of that implementation.

Run from the worktree:

```sh
python3 Tests/WrappedSeparatorReview/round2/torvalds/run.py
```

`probe.m`, `run.py`, and `results.json` provide reproducible evidence.
Generated binaries, extracted production, and logs remain under `build/WrappedSeparatorReview/round2/torvalds`.
The probe uses one explicit Menlo font and native fallback, with windowless glyph generation.
It does not test line geometry, selection, full application behavior, performance, or older macOS versions.
No production file was changed.
