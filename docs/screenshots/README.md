# README screenshots

## Current images

`readme-source.png` and `readme-dark.png` are exact copies of the light and dark User Scheme screenshots from [PR #46](https://github.com/dangduc/nv/pull/46).
Both images show plain text with an active search for `ideas`.
The [User Scheme default colors](#user-scheme-default-colors) section records their palettes, capture environment, and validation.

| Image | Content |
| --- | --- |
| `readme-source.png` | Light appearance with black text, a peach editor background, and pink search highlights. |
| `readme-dark.png` | Dark appearance with black text, a cream editor background, and yellow search highlights. |
| `readme-search.png` | Active Fuzzy search, literal title priority, duplicate occurrences, and no completed-search summary. |
| `readme-preview.png` | A read-only Markdown preview in WebKit. |
| `readme-windows.png` | Two windows with independent queries, selections, and divider heights in one shared library. |

The other three images show commit `3627e17cd88794bfc7f818e23d2ec8606af2aec5`, the defaults change in [PR #12](https://github.com/dangduc/nv/pull/12).
Their capture date is September 9, 2026, on macOS 26.5.2 (25F84), with Xcode 26.6 (17F113) and SDK 26.5.
The Intel app runs under Rosetta.
Their executable has SHA-256 `798218090127f5c89128ae718efccf7eb63d82eb86f5641b70386709f13c5ea5`.

Those captures use four sample notes, a temporary library, and a separate preferences domain.
The sample notes use Markdown syntax and the header visibility and body font defaults from PR #12.
WindowServer captures the native windows, including the WebKit preview, without annotations or pixel changes.
The original five-image capture passed 21 state and image checks.

After you refresh the User Scheme screenshots below, copy them to the README image paths:

```sh
cp docs/screenshots/user-scheme-defaults-light.png docs/screenshots/readme-source.png
cp docs/screenshots/user-scheme-defaults-dark.png docs/screenshots/readme-dark.png
```

Inspect both images before publication.

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
