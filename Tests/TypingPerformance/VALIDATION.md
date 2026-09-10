# Typing change validation

The initial production comparison uses upstream master at `8dde5e89578f99dd10751e653eb8d45c298bf72b`.
Both apps ran on macOS 26.5.2 (25F84), Xcode 26.6 (17F113), under Rosetta.
The Development build targets Intel and macOS 10.13.
These results do not establish behavior on the reported macOS 13.7.8 host.

Each app completed 1,080 checked edits across three trials per case.
Both retained immediate model commits, correct insertion offsets, 20 result notes, and a successful final checkpoint.
The benchmark contains no production skip toggles.

| Case | Keys per trial | Master main CPU | Initial change main CPU | CPU reduction | Master mean key dispatch | Initial mean key dispatch |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Short note, count hidden | 200 | 2000.1 ms | 964.6 ms | 51.8% | 2.698 ms | 3.237 ms |
| 100 KB note, count visible | 80 | 2715.0 ms | 381.0 ms | 86.0% | 25.978 ms | 6.945 ms |
| 100 KB single line, count hidden | 80 | 3741.0 ms | 616.9 ms | 83.5% | 40.217 ms | 6.828 ms |

Values are medians of three trials. Key dispatch includes synchronous event handling only.
Main-thread CPU includes deferred work and drawing during the run-loop intervals.
Reduced CPU does not imply the same reduction in visible stutter.
Short-note dispatch time increased slightly despite lower total CPU.
Physical held-key input and presented frame timing on macOS 13 remain manual checks.
The earlier space-character behavior remains outside this change.

[Master samples](measurements/master.json) and [initial change samples](measurements/initial-change.json) contain all trial measurements.
The executable SHA-256 values identify the tested binaries:

- Master: `6a9bc7b304e40072de11e2a976c7d18c89dc41188d3be82bb9deaad3a31c43a7`.
- Initial change: `1d4ca5d7db470f261a7abf458952b526f7c3c8e548fdf33a86fa06e80f3485b0`.

## Regression baseline

The required multiwindow suite and every entry in `Tests/run-regression-tests.py` ran after the initial build.
The aggregate runner stops at its first failure, so each remaining suite also ran separately.
Every failing suite was compared with the unmodified master build.

These failures also occur on master at `8dde5e8`:

| Suite | First failing behavior |
| --- | --- |
| Multiple windows and restoration canaries | Library replacement crashes after primary checks and restored-window checks pass. |
| Fuzzy search UI | The disposable browser does not become the active browser. |
| Backup archive | The coordinator does not open the validated archive as a separate library. |
| Source workflow | The fixture calls the removed `bold:` selector. |
| Native dependencies | The fixture expects HTML paste to be excluded. |
| Native UI | A menu fixture constructs an array containing a missing item. |
| Native controls | The fixture expects five syntax types and omits Org. |
| Native rendering | The expected cross-boundary search highlight is absent. |
| Ownership | The fixture requires the removed `lastImportedFindString` ivar. |
| Preview lifetime | The fixture calls the removed `beforeString` selector. |

These failures prevent a clean broad-suite result. They are not reported as passes.
The new teardown fixture also needed updates for source-analysis ownership.
Its five checks and four negative controls pass after that update.
The Exact-search Reveal failure occurred only in the candidate and became a round-one revision request.

## After round-one fixes

The Intel Development build passes with all three round-one fixes.
The native caret-click suite passes 26 checks. Editing history passes all 52 checks.
The source-analysis and typing-refresh suites still pass 63 and 35 checks.
Headless fix probes pass 11 link-publication cases, 36 Reveal checks, and 13 caret checks with two negative controls.
The old Reveal implementation fails the new control as expected.

The production benchmark again preserves all 1,080 edits, insertion offsets, and model commits.
[Reviewed samples](measurements/reviewed.json) record the three trials per case.

| Case | Master main CPU | Reviewed main CPU | CPU reduction | Master mean dispatch | Reviewed mean dispatch |
| --- | ---: | ---: | ---: | ---: | ---: |
| Short note, count hidden | 2000.1 ms | 1046.2 ms | 47.7% | 2.698 ms | 3.471 ms |
| 100 KB note, count visible | 2715.0 ms | 411.8 ms | 84.8% | 25.978 ms | 6.712 ms |
| 100 KB single line | 3741.0 ms | 614.7 ms | 83.6% | 40.217 ms | 6.763 ms |

Executable SHA-256: `d2fc91aab87fbb3937073e11908832d177559761e46237ecd597a3bd9ca5ec80`.
These measurements have the same host and interpretation limits as the initial comparison.
The link-heavy probe separately reduces 4,000-link publication from 2,848 ms to 5.9 ms, excluding layout and drawing.
See `Tests/TypingReview/fixes/link-publication/README.md` for its cases and raw output.

After the integrated build, both required runners ran again.
Multiple windows again passed its primary checks before the library-replacement crash.
The aggregate regression runner passed its earlier entries, then stopped at the same Fuzzy UI activation failure.
The independent editing-history run passed all 52 checks, so the candidate-only Reveal failure is resolved.
