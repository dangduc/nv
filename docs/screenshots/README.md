# README screenshots

## Current images

The source, search, and multiple-window images show Org syntax highlighting with the light User Scheme palette from [PR #46](https://github.com/dangduc/nv/pull/46).
The dark image shows the dark User Scheme palette with plain source text.
All four refreshed images use Fuzzy mode and show highlighted matches in the notes list.
The [User Scheme default colors](#user-scheme-default-colors) section records both palettes.

| Image | Content |
| --- | --- |
| `readme-source.png` | Light appearance with Org syntax and fuzzy highlights for `ideas` in the notes list and editor. |
| `readme-dark.png` | Dark appearance with a cream editor background and yellow fuzzy highlights in the notes list and editor. |
| `readme-search.png` | Fuzzy search for `grdn`, separate matching lines, highlighted result text, and the selected match in an Org note. |
| `readme-preview.png` | A read-only Markdown preview in WebKit. |
| `readme-windows.png` | Two Org notes with independent fuzzy queries, selections, and divider heights in one shared library. |

The four refreshed captures date from September 21, 2026, on macOS 13.7.8 with Xcode 15.2.
The Intel Development app runs under Rosetta, with application source at `be518de1d57a8d28f9b574805d01c532ef931f65`.
The executable has SHA-256 `0fccb78b9b677701d5987d9c1eb008031b7f42c33901d8379a321ec21d476849`.

The captures use disposable sample notes and a separate preferences domain.
WindowServer captures only the sample windows, with no annotations or pixel changes.
The light source capture passed 20 checks, and the dark capture passed 16 checks.
These checks include the palette, completed fuzzy results, and drawn highlight pixels in every visible result row.
The light capture also checks Org syntax colors.
The search and multiple-window captures passed 29 checks for fuzzy highlights, Org syntax, and independent browser state.
The capture app exited after each run.

The preview image shows commit `3627e17cd88794bfc7f818e23d2ec8606af2aec5`, the defaults change in [PR #12](https://github.com/dangduc/nv/pull/12).
Its capture date is September 9, 2026, on macOS 26.5.2 (25F84), with Xcode 26.6 (17F113) and SDK 26.5.
Its executable has SHA-256 `798218090127f5c89128ae718efccf7eb63d82eb86f5641b70386709f13c5ea5`.
The preview capture uses a disposable Markdown note in the native WebKit viewer.
The original five-image capture passed 21 state and image checks.

When you refresh these images, use the same palettes.
Select Fuzzy search mode for all four samples.
Select Org source syntax for the light source, search, and multiple-window samples.
Inspect each image before publication and update its capture details.

## Interaction recording

The [README demo tools](../../Scripts/readme-demo/README.md) contain the capture scripts, sample notes, encoder, and regeneration commands.

[`readme-demo.gif`](readme-demo.gif) shows fuzzy search and independent browser windows with disposable Org notes.
The recording types `grdn`, selects two matching body lines, and opens a second window to search for `trip`.
It then closes the second window and clears the first query.
The README also links to a still screenshot.

The recording lasts 20.31 seconds and loops at 1020 × 780 pixels.
The GIF contains 51 encoded frames and occupies 2,264,893 bytes (2.16 MiB).
WindowServer captured 135 frames from the sample windows, with recorded timestamps.
GIF encoding converts the monitor color profile to sRGB and leaves the background transparent.
GIF supports only fully opaque or fully transparent pixels, so this version removes the soft shadows outside the windows.
It combines unchanged frames and uses one palette with 255 colors and a transparent entry.
It preserves the recorded timing to the nearest 10 milliseconds, without captions or simulated UI elements.
The transparent version uses the same captured frames and timing as the original white-background recording.

The capture date is September 21, 2026, on macOS 13.7.8 with Xcode 15.2 and Pillow 12.2.0.
The Intel Development app runs under Rosetta, with application source at `be518de1d57a8d28f9b574805d01c532ef931f65`.
The executable has SHA-256 `0fccb78b9b677701d5987d9c1eb008031b7f42c33901d8379a321ec21d476849`.
The sample windows use the light User Scheme palette and a separate preferences domain.

The capture passed 55 checks for search input, separate matching lines, drawn row highlights, Org syntax, and independent browser state.
Automatic note selection was enabled during the capture.
Both completed fuzzy searches had a selected note before the next interaction.
Every decoded frame matches its captured frame after color, palette, and binary transparency conversion.
The decoded frames pass comparison checks on white and charcoal backgrounds, including after the second window closes.
The frame durations match the captured timing at GIF precision.
The capture app exited after the recording.

## User Scheme default colors

[`user-scheme-defaults-light.png`](user-scheme-defaults-light.png) and [`user-scheme-defaults-dark.png`](user-scheme-defaults-dark.png) show the default User Scheme palettes from [PR #46](https://github.com/dangduc/nv/pull/46).
Both images show the same sample note with an active search for `ideas`.

| Appearance | Text | Background | Search highlight |
| --- | --- | --- | --- |
| Light | `#000000` | `#FDE9D9` | `#F5C1C0` |
| Dark | `#000000` | `#FFEFC9` | `#FFC600` |

The capture date is September 21, 2026, on macOS 13.7.8 with Xcode 15.2.
The Intel Development app runs under Rosetta, with application source at `be518de1d57a8d28f9b574805d01c532ef931f65`.
The executable has SHA-256 `0fccb78b9b677701d5987d9c1eb008031b7f42c33901d8379a321ec21d476849`.
The capture uses a temporary library and a separate preferences domain with the registered color defaults.
WindowServer captures one sample window in each appearance without pixel changes.
The probe passed 21 checks, including the editor background and the text and highlight colors used for drawing.
The disposable app exited after capture.

To refresh these images after a Development build:

```sh
NV_USER_SCHEMES_ARTIFACTS="$PWD/docs/screenshots" \
  python3 Tests/ViewControlsReview/run-probe.py --probe docs/screenshots/capture-user-scheme-defaults.inc --timeout 35
```

Inspect both images before publication.

## User Scheme settings

`user-scheme-settings-light.png` and `user-scheme-settings-dark.png` show the separate light and dark palettes in Fonts & Colors.
The capture date is September 9, 2026, on macOS 26.5.2 (25F84), with Xcode 26.6 (17F113).
The Intel Development executable has SHA-256 `8060f1cb71a119e94bce789df38494c100719eaf744a4fb72df9684f7f7858f1`.
The capture uses a temporary library and preferences domain, with custom colors from the regression fixture.
WindowServer captures the native Settings window in each appearance without pixel changes.

To refresh these images after a Development build:

```sh
python3 Tests/Regression/user-schemes/run.py --artifacts build/user-schemes-artifacts
```

The final run passed 199 checks across two launches, including eight screenshot checks.
Inspect `settings-light.png` and `settings-dark.png` in that output directory before replacing the documentation images.

## Syntax colors

[`syntax-colors-light.png`](syntax-colors-light.png) and [`syntax-colors-dark.png`](syntax-colors-dark.png) show the User Scheme syntax matrix.
The capture date is September 21, 2026, on macOS 13.7.8 with Xcode 15.2.
The Intel Development app runs under Rosetta with a temporary library and preferences domain.
The images show the default syntax colors before the probe changes them.
WindowServer captures the native sheet without pixel changes.

The User Scheme command above also produces `syntax-settings-light.png` and `syntax-settings-dark.png`.
Inspect these images before replacing the documentation images.

## Product rename

[`neo-notational-v-about.png`](neo-notational-v-about.png) shows the renamed Development app in the About panel.
[`neo-notational-v-shortcut.png`](neo-notational-v-shortcut.png) shows the updated keyboard-shortcut dialog.

The capture date is September 21, 2026, on macOS 13.7.8 with Xcode 15.2.
The Intel Development executable runs under Rosetta, built from source at `18066ce736d48108109b7b8fd59f8a8cde6073eb`.
The executable has SHA-256 `a609f9fa0f5aa0f85a134f8ef8348d15843764186137a24de8eceb6f90f006b0`.
The About capture loads the updated `Resources/Help/Credits.html` into the disposable app copy.
It shows `© @dangduc, 2026` above the upstream credits.
The captures use a disposable notes library and a separate preferences domain.
WindowServer captures the native app windows without pixel changes.
The disposable app exited after capture.

## Search placement

[`search-below-title-bar.png`](search-below-title-bar.png) shows the default search row between the window title bar and notes list.
[`search-in-title-bar.png`](search-in-title-bar.png) shows the optional compact layout selected through View > Search in Title Bar.

The capture date is September 22, 2026, on macOS 13.7.8 with Xcode 15.2.
The Intel Development app runs under Rosetta with disposable notes and a separate preferences domain.
WindowServer captures the native window without annotations or pixel changes. The capture app exits after the checks.

To refresh these images after a Development build:

```sh
mkdir -p build/search-placement-artifacts
NV_UI_ARTIFACTS="$PWD/build/search-placement-artifacts" \
  python3 Tests/Regression/native-controls/run.py --probe placement
```

Inspect both images in that directory before replacing the documentation copies.

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

## Org source

`org-source.png` shows Org source support on September 9, 2026.
The Intel Development app ran through Rosetta on macOS 26.5.2 with Xcode 26.6.
The Org integration suite captured a disposable library after the native window drew its content.
The title and source controls are visible to identify the selected syntax. The image has no pixel changes.

To refresh this image after a Development build:

```sh
NV_UI_ARTIFACTS="$PWD/build/org-integration-artifacts" python3 Tests/OrgSource/Integration/run.py
```

## Org preview

`org-preview.png` shows the Org viewer on September 9, 2026.
The Intel Development app ran through Rosetta on macOS 26.5.2 with Xcode 26.6.
The capture uses a disposable library and preferences domain.
WindowServer captures the native window without pixel changes.
The executable has SHA-256 `8b5223f71a9a71246a1de7184df76a1ed1fdce4a0c1f151345287acd3d0d81c0`.

To refresh this image after a Development build:

```sh
NV_UI_ARTIFACTS="$PWD/build/org-preview-artifacts" python3 Tests/Regression/org-preview-ui/run.py
```

The capture run passed 59 checks. Inspect the output image before replacing this file.

## Side notes list

`notes-list-side.png` shows the side list with Search below the title bar.
`notes-list-side-title-bar.png` shows the same list with Search in the title bar.
Both captures show separate title and body results with fuzzy match highlights.

Captured on September 22, 2026, on macOS 13.7.8 with Xcode 15.2.
The unsigned Intel Development app ran under Rosetta with disposable notes and preferences.
The files are native WindowServer captures without pixel edits.

To regenerate:

```sh
mkdir -p build/side-list-artifacts
NV_UI_ARTIFACTS="$PWD/build/side-list-artifacts" \
  python3 Tests/Regression/native-controls/run.py --probe layout
```

Inspect the captures before copying them into this directory.

## Adaptive notes-list colors

`adaptive-list-light-body-stacked.png` and `adaptive-list-light-body-side.png` show peach paper inside a dark window.
`adaptive-list-dark-body-stacked.png` and `adaptive-list-dark-body-side.png` show a dark blue body inside a light window.
The list uses the body palette in both layouts. Column titles and header backgrounds use the same colors.
Both fuzzy title and body results retain their match highlights.

Captured on September 23, 2026, on macOS 13.7.8 with Xcode 15.2.
The unsigned Intel Development app ran under Rosetta with disposable notes and preferences.
These files are native WindowServer captures without pixel edits.

To regenerate:

```sh
mkdir -p build/adaptive-list-artifacts
NV_UI_ARTIFACTS="$PWD/build/adaptive-list-artifacts" \
  python3 Tests/Regression/native-controls/run.py --probe colors
```

Inspect the four captures before copying them into this directory.

## Tab key settings

`tab-key-settings.png` shows the restored Editing controls and the fixed Option-Tab and Shift-Tab shortcuts.
Captured on September 23, 2026, on macOS 13.7.8 with Xcode 15.2.
The unsigned Intel Development app ran under Rosetta with disposable notes and preferences.
The image is a native WindowServer capture without pixel edits.

To regenerate, set `NV_UI_ARTIFACTS` to an existing directory and run:

```sh
python3 Tests/Regression/native-controls/run.py --probe tab-preference
```
