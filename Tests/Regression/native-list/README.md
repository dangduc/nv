# Native list appearance checks

The native UI acceptance fixture includes these checks during its Aqua and Dark Aqua appearance cases. It creates three notes and enables native alternating rows. It samples two unselected rows of opposite parity.

The helper captures the containing content view. Thus, native row transparency composites over the scroll-view content during AppKit drawing. The checks require opaque rendered rows, pale backgrounds, and dark title glyph pixels. The glyph sample excludes row edges and grid lines.

Each row must contain more than 1,000 pixels and more than 99% opaque pixels. Its median brightness must exceed 0.85. More than 70% of its opaque pixels must exceed brightness 0.85. The title region must contain more than ten pixels below brightness 0.3.

Run the acceptance fixture after the Development build:

```sh
python3 Tests/Regression/native-ui/run.py
```

When `NV_UI_ARTIFACTS` names an existing directory, the fixture saves each row bitmap beside the window snapshots. These checks exercise AppKit bitmap drawing. They do not measure final desktop compositor output or accessibility contrast compliance.

The Round 3 correction runner applies the original review fault to a copied app:

```sh
python3 Tests/NativeUIReview/round3/corrections/run-list-canary.py
```

It requires the current fixture to pass without the fault. The same fixture must reject removal of the list's forced Aqua appearance. The historical finding at source `0afeb038` remains under `Tests/NativeUIReview/round3/test_contrarian/`. Its original acceptance result describes that revision. The corrected fixture now checks the rendered list.
