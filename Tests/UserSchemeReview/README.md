# User Scheme light and dark palettes

[PR #16](https://github.com/dangduc/nv/pull/16) gives User Scheme separate palettes that follow each browser's effective appearance.
Existing color preferences remain the light palette. Fonts & Colors exposes both groups; the menu keeps one User Scheme option.
The implementation is in `3297f6e`, with review fixes in `0fc7aca` and `da052b2`.

## Review results

Both rounds are complete. Each reviewer wrote and ran code, then reported the evidence and its limits.
The named perspectives draw on those engineers' priorities. They do not claim their authorship or endorsement.
Check counts include setup assertions and can overlap; they do not measure coverage.

| Round | Perspective | Result | PR comment |
| --- | --- | --- | --- |
| 1 | [Ousterhout](round1/ousterhout/report.md) | 108 checks passed; four schemes and independent browser palettes | [Comment](https://github.com/dangduc/nv/pull/16#issuecomment-5610138664) |
| 1 | [Luu](round1/luu/report.md) | 148 checks passed; syntax attributes and parse work across appearance changes | [Comment](https://github.com/dangduc/nv/pull/16#issuecomment-5610143201) |
| 1 | [Torvalds](round1/torvalds/report.md) | 35 general checks passed; P1 availability failure reproduced and fixed | [Comment](https://github.com/dangduc/nv/pull/16#issuecomment-5610153505) |
| 1 | [Kingsbury](round1/kingsbury/report.md) | 80 checks passed; stale asynchronous callbacks and window replacement | [Comment](https://github.com/dangduc/nv/pull/16#issuecomment-5610210186) |
| 1 | [Contrarian](round1/contrarian/report.md) | 242 checks passed; six localized panes and native color-panel routing | [Comment](https://github.com/dangduc/nv/pull/16#issuecomment-5610213929) |
| 2 | [Ousterhout](round2/ousterhout/report.md) | 109 checks passed; independent nested-scope validation of the compatibility fix | [Comment](https://github.com/dangduc/nv/pull/16#issuecomment-5610287526) |
| 2 | [Luu](round2/luu/report.md) | P2 named-color failure reproduced; the compiled fix passed 27 checks | [Comment](https://github.com/dangduc/nv/pull/16#issuecomment-5610332963) |
| 2 | [Torvalds](round2/torvalds/report.md) | 55 checks and availability compilation passed; independent editor-fix validation | [Comment](https://github.com/dangduc/nv/pull/16#issuecomment-5610338025) |
| 2 | [Kingsbury](round2/kingsbury/report.md) | 86 checks passed; composition, palette persistence, and note restart | [Comment](https://github.com/dangduc/nv/pull/16#issuecomment-5610293183) |
| 2 | [Contrarian](round2/contrarian/report.md) | 38 checks passed; global highlight toggle and active color-panel behavior | [Comment](https://github.com/dangduc/nv/pull/16#issuecomment-5610302037) |

Two findings required production changes:

- P1: User Scheme reached a macOS 11 API under a macOS 10.14 guard. `0fc7aca` corrects the guard and restores caller appearance through an exception-safe fallback.
- P2: The new dark highlight slot could resolve native named colors under the callback's ambient appearance. `da052b2` resolves them under the editor's appearance.

Both fixes have reproductions, controls, maintained regression checks, and independent second-round verification.
The [compatibility report](fixes/appearance-compatibility/report.md) records both rejected negative controls.
Older-system branches were simulated on the current host; no actual older macOS installation was tested.
The named-color limitation existed in the historical light helper; the second finding concerns its extension to the new dark slot.

## Final validation

The Intel Development build passed on macOS 26.5.2 (25F84), Xcode 26.6 (17F113), through Rosetta.
The final executable SHA-256 is `3e8ebdc2258bd0d402e56066e6dd649ed7c277b4c6b05f95566a7e468df0dbf9`.
This identifies the tested local build; it is not a requirement for other builds.

```sh
python3 Tests/Regression/user-schemes/run.py
```

The final combined runner passed 234 checks: 16 compatibility checks, 191 palette and restart checks, and 27 dynamic-color checks.
It also passed compilation of the unchanged browser appearance method with availability errors enabled for macOS 10.13.
The second-round editor review separately passed the corresponding compilation check for the highlight helper.
The focused HighlightBounds suite passed 106 checks; the final aggregate run also passed that stage.

The complete desktop suites remain failing:

- `Tests/run-multiple-windows-tests.py` stops at the shared-text exception: index 13, string length 12.
- `Tests/run-regression-tests.py` passes the native search stages, then fails `fuzzy workflow owns active disposable browser`.

Both failures were already recorded in the [prior Command-N review](../FocusedSearchNewNoteReview/README.md#validation).
An intermediate aggregate attempt met an occupied GUI lock. The final attempt ran without that contention and reached the known activation failure.
The composition review also records a direct-unmark exception and its control; that evidence does not attribute the exception to this PR.

Local build and final suite logs are under `build/user-scheme-dynamic-build.log` and `build/user-scheme-final-*.log`.
The [Settings screenshots](../../docs/screenshots/README.md#user-scheme-settings) show the original implementation before the behavior-only review fixes.
