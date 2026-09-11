# Round 3: ASCII shortcut correctness

No actionable findings in `e022109eaf2bad6583512c2ed2b48561d9dae011`, compared with `2ea92180939a3e51df8fe867ad548140ed455868`.
This review uses a Torvalds-inspired engineering perspective.

The correction preserves the checked glyph behavior and restricts its shortcut to printable ASCII neighbors.
At `Sources/Editor/LinkingEditor.m:312`, the existing interior-range guard protects both adjacent UTF-16 reads.
The predicate at line 316 includes U+0021 through U+007E and excludes U+0020 and U+007F.
The fallback at line 318 retains Foundation's composed-range query when either neighbor is outside that interval.

The new native probe passed **171,497 checks on each architecture**, arm64 and x86_64.
Both runs produced identical summaries on macOS 26.5.2, build 25F84, with Xcode 26.6, build 17F113.
The runner extracts both complete frozen callbacks without changing their bodies.
`results.json` records their hashes and the probe hashes.

Foundation independently checked every printable ASCII neighbor pair: **94 × 94 = 8,836 pairs**.
Each pair was checked in seven contexts, for **61,852 observations**.
These contexts include plain text, prepend characters, combining marks, ZWJ emoji, bidi isolation, paragraph separators, and supplementary variation selectors.
Every queried space had exactly its own one-unit UTF-16 composed range.

Four native batches compare both production callbacks and a layout manager without a delegate.
The property oracle always queries Foundation and contains no ASCII shortcut.

| Native batch | Eligible spaces | Elastic retained | Elastic removed |
| --- | ---: | ---: | ---: |
| All printable ASCII pairs | 8,836 | 8,836 | 0 |
| Selected pairs with non-ASCII surroundings | 96 | 96 | 0 |
| U+0020/U+0021/U+007E/U+007F pairs and paragraph edges | 27 | 9 | 18 |
| Unicode fallback and composed spaces | 86 | 28 | 58 |

All 36,525 glyphs preserve their IDs, UTF-16 mappings, bidi levels, and counts.
Source text and attributes match the native baseline.
Properties before and after the correction match exactly, and only the permitted Elastic removal differs from native generation.
The fallback batch includes every Foundation whitespace member, selected zero-width controls, combining marks, VS16, ZWJ, and supplementary scalars.

Run from the worktree:

```sh
python3 Tests/WrappedSeparatorReview/round3/torvalds/run.py
```

`probe.m`, `run.py`, and `results.json` provide reproducible evidence.
Generated binaries and logs remain under `build/WrappedSeparatorReview/round3/torvalds`.
The probe uses windowless glyph generation with Menlo and native font fallback.
It does not measure performance or test line geometry, application editing, older macOS versions, or every possible surrounding Unicode sequence.
No production file was changed.
