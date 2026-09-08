# Syntax color screenshots

These native screenshots compare the same Markdown edit before and after the fix.
The probe holds analysis after the first completed parse so WindowServer can capture the pending state.
It does not change the drawing delegate or temporary attributes.
This controlled pause illustrates the color gap. It does not measure the gap's duration during normal typing.

The baseline app was built from `162c872`, with the same highlighter and drawing delegate as the PR base `8cd2c95`.
The fixed app was built from `65e1608`.
Both runs use copied apps, separate preferences, and disposable notes.

From the repository root, use the corresponding app and screenshot paths:

```sh
NV_FLICKER_SCREENSHOT="$PWD/docs/screenshots/source-syntax-flicker-before.png" \
  python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/SyntaxFlickerReview/visual/probe.inc \
  --prefix Tests/SyntaxFlickerReview/visual/prefix.h \
  --app build/ViewControlsReview/round1/nvALT.app
NV_FLICKER_SCREENSHOT="$PWD/docs/screenshots/source-syntax-flicker-after.png" \
  python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/SyntaxFlickerReview/visual/probe.inc \
  --prefix Tests/SyntaxFlickerReview/visual/prefix.h \
  --app build/SyntaxFlickerReview/fix.app
```

Both runs passed seven checks. The baseline displays plain source while the fixed app retains syntax colors.
The permanent source-workflow regression also checks the drawing delegate immediately after native edits, without this controlled pause.
