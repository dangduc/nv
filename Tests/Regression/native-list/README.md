# Native list appearance checks

The native UI fixture creates three notes and samples two unselected rows of opposite parity.
It checks system and custom body palettes through Aqua, Dark Aqua, and return transitions.

The table, scroll view, and clip view must use the body background.
Their native appearance follows the body brightness, independently of the window theme.
Custom editor colors must remain unchanged during these appearance changes.

The helper captures the containing content view, including native selection and the scroll-view background.
The glyph sample excludes row edges and grid lines. Expected colors convert to the bitmap's display profile for comparison with captured bytes.

Each row must contain more than 1,000 pixels and more than 99% opaque pixels.
More than 70% must match the expected background within 0.025 per channel.
Odd alternating rows use a 5% blend toward white or black, according to the body brightness.
More than ten title pixels must match the body foreground within 0.15 per channel.

Run the focused cache fixture on the host architecture:

```sh
python3 Tests/Regression/native-list/run-native.py
```

It uses the production preview formatter and tag-image method with fixed font preferences.
It checks cached text, tag colors, and visible tag words through Aqua, Dark Aqua, and a return to Aqua.
Its bitmap images contain sample text and tags. They do not show a complete browser window or exercise application startup.
The `--negative-control` option restores the obsolete glyph operation and requires the visible-word check to fail.

Run the acceptance fixture after the Development build:

```sh
python3 Tests/Regression/native-ui/run.py
```

When `NV_UI_ARTIFACTS` names an existing directory, the fixture saves each row bitmap beside the window snapshots. These checks exercise AppKit bitmap drawing. They do not measure final desktop compositor output or accessibility contrast compliance.

The native-controls `--probe colors` fixture also checks both layouts with body palettes opposite to the window themes.
It checks focused and unfocused selection, independent browser palettes, and changes without shared-source edits.

The historical finding at source `0afeb038` remains under `Tests/NativeUIReview/round3/test_contrarian/`.
The historical correction runner under `Tests/NativeUIReview/round3/corrections/` assumes forced Aqua.
Those records describe earlier requirements and are not current regression commands.
