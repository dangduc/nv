# Wrapped separator validation

Initial implementation: `9e6c8dd6adc058e7044f2c562532af97dd4e63d4`.
Host: macOS 26.5.2 (25F84), Xcode 26.6 (17F113).
Intel probes ran through Rosetta. The Development app targets macOS 10.13.

The Development build passed.
The focused production-delegate checks passed on both architectures.

| Suite | arm64 assertions | x86_64 assertions |
| --- | ---: | ---: |
| Separator geometry | 2,164 | 2,164 |
| Shared-layout transitions | 7,952 | 7,952 |
| Preserved whitespace and composed characters | 200 | 200 |
| Total | 10,316 | 10,316 |

The geometry suite contains 684 font, width, and source cases with 795 automatic line boundaries.
Both negative controls failed at the expected leading-gap assertion with the former fixed-width policy.

The copied-app suite passed 32 checks using the actual source editor and shared note model.
It covers exact-width geometry, native Space, shared Undo/Redo, private copy/paste, note switching, and preserved whitespace.
The tested executable SHA-256 is `f1918d1d728fe257fe76368cebaadee2625ac3bc8688ab7c3b3cef977ec22384`.
The [synthetic note screenshot](../../docs/images/wrapped-separators/source.png) shows automatic wraps and preserved indentation.
The bitmap includes native window views but omits the final window-server composition and shadow.
All [three review rounds](../WrappedSeparatorReview/STATUS.md) are complete.
Each round contains six code-writing reviews.
The round-two performance finding was corrected before round three, which verified its resolution.

## Correction after round two

Commit `e022109eaf2bad6583512c2ed2b48561d9dae011` addresses the measured ASCII performance finding.
Both neighbors must be printable ASCII before the callback skips the composed-character query.
All other eligible separators retain the complete Foundation check.

The corrected Development build passed.
The focused checks again passed 10,316 assertions per architecture, and both negative controls rejected the old wrap behavior.
The copied-app separator checks passed 32 assertions.
The corrected executable SHA-256 is `b28da33e5f645a589f4802d778225693f7e0764abf6a48a21690d154421ad40c`.

Both required desktop suites ran again against this app.
The multiwindow suite exited 245 after opening the replacement library.
The aggregate suite passed the wrapping and separator checks, then stopped at the same Fuzzy UI activation failure described below.
Later aggregate entries did not run. These remain incomplete suite results.

Round three compared the committed correction with the pre-fix implementation.
The large ASCII start-edit pair improved from 132.004 to 118.855 milliseconds in that separate benchmark.
Glyph properties, positions, and line geometry matched; Unicode fallback remained active.
These are layout measurements on this host, not full-application keystroke timings.
The corrected production commit also passed [CI](https://github.com/dangduc/nv/actions/runs/34643467685).

## Existing desktop failures

The required multiwindow runner passed its initial and restoration checks, then exited 245 after opening the replacement library.
This matches the documented [regression baseline](../TypingPerformance/VALIDATION.md#regression-baseline).
It is a failure, not a complete suite pass.

The aggregate runner passed the source-editing, word-wrapping, separator, list, Org, and preceding fuzzy-search checks.
It then stopped at `FuzzySearch/UI`: `fuzzy workflow owns active disposable browser`.
This is also in the recorded regression baseline.
Later aggregate entries did not run. The complete aggregate suite did not pass.
The word-wrapping suite passed 74,736 assertions per architecture, including its layout timing checks.
Its copied-app suite passed 1,305 assertions. The new copied-app separator suite passed 32 assertions.
macOS 13.7.8, physical key repeat, and presented frame timing remain manual validation limits.
