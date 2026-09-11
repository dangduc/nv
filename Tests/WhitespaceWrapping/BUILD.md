# Space-wrapping Development builds

Built on macOS 26.5.2 (25F84) with Xcode 26.6 (17F113).
The application is Intel x86_64 with a macOS 10.13 deployment target.
Apple Silicon hosts require Rosetta.

The build uses merged master `f772c4b` plus the layout adjustment in `LinkingEditor`.
The adjustment clears the elastic glyph flag for ordinary spaces during native glyph generation.
It changes display layout without changing stored characters or keyboard commands.

## Current review build

The review correction combines the glyph adjustment with native character wrapping.
Words can split at the window edge, and overflowing spaces leave an already-fitting word in place.
One immutable paragraph style is shared across note-body attribute requests.

The current executable SHA-256 is `be02dd1fe33a39c74b8961441be55f4f91378d46935bdba99fd610d405c3e09b`.
The [review record](../WhitespaceWrapReview/STATUS.md) links correction evidence and later review rounds.
The results and ZIP listed below describe the initial glyph-only build.

## Initial test-build artifacts

- Application: `build/DerivedData/Build/Products/Development/nvALT.app`
- ZIP: `build/WhitespaceWrapping/nvALT-Space-Wrap.zip`
- Executable SHA-256: `6682e85cff4069c18b65ef9989830de2b72c3513240302a197395551d53d7d0c`
- ZIP SHA-256: `c844e37b55ec3cbb4a927ff9eabc41fe58b39a637414da2236bd2ebe1eb37562`

The ZIP integrity check passed. The build is unsigned and not notarized.
Quit any other nvALT process before opening this build for manual comparison.
The normal application uses the existing nvALT preferences and library.
The automated checks described here used copied apps with disposable libraries.

## Validation

The Development build succeeded with existing compiler and analyzer warnings.
The 843-check space-wrapping app probe passed.
It sent 804 repeated Space events through the actual editor in Plain Text and Markdown at two font sizes.
It checked source preservation, wrapped caret geometry, Backspace, Undo, different window widths, and resizing.

The aggregate regression runner passed source analysis, typing refresh, source deletion, native editing, Org, and the preceding fuzzy-search checks.
The deletion suite passed 310 checks, and the native editing suite passed 57 checks.

The required desktop runners retained their previously documented failures:

- `run-multiple-windows-tests.py`: exit 245 after the replacement library opened during relaunch.
- `run-regression-tests.py`: stopped at the Fuzzy UI assertion about the active disposable browser.

These failures also occurred on the unchanged master application in the prior [baseline validation](../TypingPerformance/VALIDATION.md).
The complete desktop suites are therefore not reported as passing.
The wrapper records each command, exit status, and log path in `build/WhitespaceWrapping/validation.json`.

The typing benchmark passed all 1,080 checked edits with the packaged executable.
Each case ran three trials.
Median main-thread CPU totals were 1,037.9 ms for short notes, 427.0 ms with visible word count, and 651.1 ms for a long line.
Compared with the earlier PR #24 measurements, these totals changed by -0.8%, +3.7%, and +5.9%, respectively.
The comparison uses separate runs and does not establish statistical significance or a bound on frame latency.
Raw benchmark results are in `build/WhitespaceWrapping/performance/`.

## Manual validation

The user reports that this build appears to solve the reported caret issue.
The affected host was previously identified as macOS 13.7.8.
The automated checks ran on macOS 26.5.2 and do not independently establish behavior on the other host.
The automated geometry checks force layout and do not capture every displayed animation frame.
