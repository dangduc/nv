# Native list appearance checks

The native UI acceptance fixture creates three notes and samples two unselected rows of opposite parity. It checks Aqua, Dark Aqua, and a return to Aqua with native alternating rows. It also checks Dark Aqua, Aqua, and a return to Dark Aqua with plain rows and custom editor colors.

The table, scroll view, and clip view must inherit the window appearance. Their background colors must match that appearance. Custom editor colors must remain unchanged during these appearance changes.

The helper captures the containing content view. Native row transparency thus composites over the scroll-view content during AppKit drawing. The glyph sample excludes row edges and grid lines.

Each row must contain more than 1,000 pixels and more than 99% opaque pixels. Each appearance has these additional limits:

| Appearance | Median row brightness | Background pixels | Title glyph pixels |
| --- | --- | --- | --- |
| Aqua | More than 0.85 | More than 70% have brightness greater than 0.85 | More than ten have brightness less than 0.3 |
| Dark Aqua | Less than 0.3 | More than 70% have brightness less than 0.3 | More than ten have brightness greater than 0.65 |

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

The historical finding at source `0afeb038` remains under `Tests/NativeUIReview/round3/test_contrarian/`. The original requirement kept the list light in both appearances. The historical correction runner under `Tests/NativeUIReview/round3/corrections/` assumes forced Aqua. It is not a current regression command. Those records do not describe the current requirement to use system colors.
