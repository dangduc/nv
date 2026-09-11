# Notes-list redraw regression

Build the Intel Development app, then run these commands from an active desktop session:

```sh
python3 Tests/ListRedraw/run.py
python3 Tests/ListRedraw/run.py --label negative --negative-control
```

The runner copies the app, gives it a private preferences domain, and creates 24 disposable notes.
It captures the list from its opaque ancestor, which supplies the background for partial redraws.
The same bitmap receives 101 draws across 100 divider-size changes between 320 and 350 points.

The check compares every pixel before and after the size changes.
It also checks opaque row backgrounds and the expected light or dark brightness.
The cases cover Aqua and Dark Aqua with alternating rows enabled and disabled.
The runner saves logs, results, and final PNG captures under `build/ListRedrawFix/<label>/`.

The negative control installs the obsolete `isOpaque` override on `NotesTableView` in the disposable process.
It succeeds only when the pixel comparison detects accumulated drawing.
It does not change the superclass implementation or the application binary.

These checks exercise native bitmap drawing and programmatic divider changes.
They do not capture final desktop compositing or physical mouse dragging.
Dark Aqua requires macOS 10.14 or later.

## Validation

The Intel Development build passed on macOS 26.5.2 with Xcode 26.6 (17F113), targeting macOS 10.13.
The corrected app passed all 31 redraw checks.
The negative control failed the pixel comparison as expected.
The required desktop suites retained the documented library-replacement and Fuzzy UI focus failures.
See the [baseline validation record](../TypingPerformance/VALIDATION.md#regression-baseline).
