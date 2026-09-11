# Development build validation

Host: macOS 26.5.2 (25F84), Xcode 26.6 (17F113). Applications use Intel binaries through Rosetta.

At implementation commit `2dbfd46`:

- `Notation Develop` and `Notation Release` builds passed with the documented unsigned Intel options.
- Both built apps passed `.github/scripts/check-app-identity.py`.
- The release ZIP passed `.github/scripts/check-app-archive.py`.
- All 23 CI unit tests passed.
- `runtime/run.py` passed Development, release, and missing-flavor cases.
  It covers temporary paths, intercepted keychain operations, and automatic legacy import.
  The probe does not call the real keychain API.

The required desktop suites ran against the renamed Development app:

- Multiple Windows passed normal operation and relaunch checks, then exited 245 after opening the replacement library.
- The regression suite passed through source analysis, editing, wrapping, and native fuzzy-search checks.
  It stopped at `FuzzySearch/UI`: `FAIL: fuzzy workflow owns active disposable browser`.

Both failures match the existing [baseline record](../TypingPerformance/VALIDATION.md#regression-baseline).
Later tests in the aggregate command did not run after its first failure.
The source-analysis and Org-link fixtures now include the new identity header when they extract production link methods.

The applications still require separate custom notes folders when both processes run.
The isolation does not coordinate simultaneous writes to a deliberately shared library.

`run-tests.py --output build/DevelopmentBuild` passed 138 in-app checks, plus bundle metadata and concurrent-process checks.
Both apps ran together during the first launch and again during relaunch.
The probe checked notes, backup payloads, font/color preferences, separate paths, legacy-import behavior, and the DEV badge state.
The copied apps used unique test preference domains and redirected filesystem roots.
Real keychain and external-editor integration remain outside this test's scope.

Native content snapshots show independent color and font settings in disposable notes:

| Development | Release |
| --- | --- |
| ![Development test content](../../docs/images/development-build/development.png) | ![Release test content](../../docs/images/development-build/release.png) |

These AppKit bitmaps contain the content view. They do not capture the system Dock or window frame.
