# Round 2: hard-break indentation and paragraph metrics

Reviewed frozen production `2ea92180939a3e51df8fe867ad548140ed455868` against `75d6f4269d5c3f0ff2d3df392659ccf95bc1482b`.
No actionable findings arose in these bounded cases.
Both arm64 and x86_64 passed 252 assertions across ten cases each.

The runner extracts both exact glyph callbacks and the frozen production typesetter through `git show`.
It does not use the experimental ASCII classifier.
`results.json` records source hashes, environment details, indentation advances, and each result.

The two source fixtures contain CRLF, CR, LF, U+2028, and U+2029 in opposite orders.
Each hard break has one indentation space before a single letter.
Both fixtures also contain an isolated separator at a soft wrap.

Each live text system undergoes five metric phases:

| Font size | Fragment padding | First-line indent | Continuation indent |
| --- | --- | --- | --- |
| 10 points | 0 | 0 | 0 |
| 10 points | 5 | 0 | 0 |
| 22 points | 9 | 0 | 0 |
| 22 points | 5 | 8 | 12 |
| 10 points | 0 | 0 | 0 |

Every phase compares the live layout with a fresh production layout, the baseline callback, and native word wrapping.
The font is Menlo.
All live character positions and glyph properties match the fresh production layout after each metric change.
Source characters and paragraph attributes remain unchanged during layout.
The mixed hard-break code units remain exact.

All 50 indentation checks per architecture retain a nonelastic space.
Each indentation space advances on the same line as its following letter.
Its horizontal origin and advance match the baseline.

The isolated soft-wrap separator remains on the preceding line.
The following word begins at fragment padding plus the continuation indent, matching the native word layout.
The baseline differs in all ten control layouts per architecture.

## Reproduction and limits

Run from the repository root:

```sh
python3 -B Tests/WrappedSeparatorReview/round2/platform/run.py
```

The host ran macOS 26.5.2 (25F84) with Xcode 26.6 (17F113).
Rosetta ran the Intel executable with a macOS 10.13 deployment target.
The arm64 executable targets macOS 11.0.
These results do not establish behavior on macOS 13 or any other older runtime.

The probe uses native text storage, layout managers, and text containers without an application or GUI session.
It covers paragraph attributes applied to text storage, not the full editor's paste, import, or save normalization.
It does not cover screen scaling, physical input, painted geometry, or every paragraph style.
No production files, user preferences, notes, keychain items, commits, or PR comments changed.
The runner deletes its temporary sources and executables after completion.
