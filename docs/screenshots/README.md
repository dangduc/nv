# README screenshots

## Current images

The five `readme-*.png` images show the Development app from commit `3627e17cd88794bfc7f818e23d2ec8606af2aec5`.
This is the defaults change in [PR #12](https://github.com/dangduc/nv/pull/12).
The capture date is September 9, 2026, on macOS 26.5.2 (25F84), with Xcode 26.6 (17F113) and SDK 26.5.
The Intel app runs under Rosetta.

| Image | Content |
| --- | --- |
| `readme-source.png` | Editable Markdown source, the monospace body font, and hidden header rows. |
| `readme-dark.png` | The same note with system colors in the editor and notes list. |
| `readme-search.png` | Active Fuzzy search, literal title priority, duplicate occurrences, and no completed-search summary. |
| `readme-preview.png` | The same source as a read-only Markdown preview in WebKit. |
| `readme-windows.png` | Two windows with independent queries, selections, and divider heights in one shared library. |

The capture uses four sample notes, a temporary library, and a separate preferences domain.
Markdown syntax is selected for the sample notes. New notes still start as Plain Text.
The header visibility and body font use the defaults from PR #12.
The capture selects light or dark appearance and disables search autocomplete for stable queries.

The app builds from the normal Development scheme.
A probe through `Tests/ViewControlsReview/run-probe.py` opens the sample notes and selects the native app states.
WindowServer captures each complete window, including the WebKit preview.
The two-window image includes only the two sample window IDs.
The images contain no annotations or pixel changes.
The capture run passed 21 state and image checks.

The captured executable has SHA-256 `798218090127f5c89128ae718efccf7eb63d82eb86f5641b70386709f13c5ea5`.
The README changes contain no application code. Merge the defaults change before the README describes these settings as defaults.

## Historical images

Earlier images remain available for the review records that link to them.

The original three images show the Development app from revision `379f09a`, captured on September 7, 2026.
The host ran macOS 13.7.8 with Xcode 15.2. The Intel app ran under Rosetta.

- `native-light.png` shows the full library in light appearance.
- `native-dark.png` shows the same note in dark appearance.
- `multiple-windows.png` shows two windows with separate searches and divider heights.

All notes are sample content. The capture used a temporary library and a separate settings domain.
The capture skipped sync, update checks, and external editor initialization.
The images contain native app windows without annotations or changes to the pixels.

`source-editor.png` and `readonly-viewer.png` show the source redesign on September 8, 2026.
The host ran macOS 26.5.2 with Xcode 26.6 and SDK 26.5. The Intel app ran under Rosetta.
The `source-workflow` regression suite captured the native window after its next frame was presented.
These images contain disposable source fixtures, with no annotations or pixel changes.

To refresh this pair after a Development build:

```sh
NV_UI_ARTIFACTS="$PWD/build/source-viewer-artifacts" python3 Tests/Regression/source-workflow/run.py
```

Inspect `editable-source.png` and `readonly-preview.png` in that output directory before replacing the two documentation images.

## Refresh the original images

1. Build the app with the command in the [main README](../../README.markdown#build-and-run).
2. Use a disposable library with sample notes.
3. Capture the light and dark appearances of one window.
4. Capture two windows with different searches.
5. Replace the PNG files in this directory.
6. Update the revision and environment in this file.
