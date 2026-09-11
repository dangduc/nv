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
The three review rounds are in progress.

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
