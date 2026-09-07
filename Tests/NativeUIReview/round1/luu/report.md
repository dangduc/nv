# Round 1: measurement and rendering review

This review applies a Dan Luu-inspired measurement perspective. It does not represent Dan Luu.

Scope: source `10de8a4` against `116daff`, and the supplied Development app copies. The host used macOS 13.7.8 and Intel binaries under Rosetta.

## Finding: P2 — Disabled clickable URLs disappear on dark editor backgrounds

Location: `LinkingEditor.m:406-408`.

When `MakeURLsClickable` is false, `preferredLinkAttributes` returns an empty dictionary. Typed URLs still retain their `NSLinkAttributeName` attribute. The new delegate therefore returns without a display foreground for those runs. Their stored black foreground remains active while ordinary text uses the white foreground.

The isolated probe types a URL through `LinkingEditor`, disables clickable URLs, and applies a white-on-black editor theme. The current app renders ordinary text at brightness `1` and the URL at brightness `0`. The URL disappears in the captured bitmap. The baseline renders both at brightness `1` and passes the same assertion.

Expected behavior: URL text remains readable when the user disables clickable URLs. The renderer can use the ordinary foreground when a link has no preferred foreground.

Reproducer from the repository root:

```sh
NV_LUU_ARTIFACT="$PWD/Tests/NativeUIReview/round1/luu/link-disabled.png" \
  python3 Tests/NativeUIReview/round1/luu/run.py --case links
```

The command exits `1` on the reviewed build. Add `--app build/UIDerivedDataBaseline/Build/Products/Development/nvALT.app` to check the passing baseline.

Evidence: `checks.inc`, `link-disabled.log`, `link-disabled-baseline.log`, and the corresponding PNG files in this directory. The probe combines the actual editor insertion path, the layout delegate result, and an AppKit bitmap capture. It does not depend only on a manually constructed link attribute.

## Measurement checks without findings

The performance probe uses 10,000 deterministic notes. Field-editor insertions exercise the application callback, table selection, and body selection. Assertions check each query, its result count, and the unchanged note count.

| Operation | Baseline median / p95 (ms) | Current median / p95 (ms) |
| --- | --- | --- |
| Four field-editor queries, 12 samples | 49.20 / 50.93 | 48.44 / 53.77 |
| Table scroll and bitmap capture, 30 samples | 8.69 / 16.15 | 8.43 / 15.64 |
| Window resize and layout, 20 samples | 1.82 / 3.95 | 3.23 / 5.64 |
| 256 KiB body bitmap, 8 samples | 0.98 / 10.52 | 1.17 / 11.31 |
| 1 MiB body bitmap, 8 samples | 0.93 / 9.31 | 1.12 / 10.52 |

Both table viewports measured 625 × 132 points. Both body captures used 600 × 180 points. Bodies contain parsed links. The first reveal plus forced full layout of the 1 MiB body took 428.60 ms before and 437.04 ms after.

The resize sample adds about 1.4 ms to the median. These measurements do not establish a user-visible performance regression. Forced full layout includes work beyond the visible text. Bitmap capture does not measure scrolling frame rate. These results represent one final paired run, with small sample counts and no confidence intervals.

The existing `VALIDATION.md` correctly describes its lower-level filter and bitmap measurements. I found no unsupported frame-rate claim.

Reproduce the measurements with `run.py --case perf`. Add the baseline `--app` argument for comparison. Logs are `perf-baseline.log` and `perf-native.log`.

## Isolation and limits

Every GUI run acquires `build/pr-review/gui.lock`. The runner copies the app, assigns a unique bundle identifier, and uses temporary notes and support directories. It skips normal startup services and bounds the app process to 90 seconds. No production files or live notes changed. No rebuild occurred during this review.

The link check failed as intended on the reviewed build. Both final performance runs passed. This review did not exercise live sync, unlocked full screen, other macOS versions, or accessibility contrast settings.
