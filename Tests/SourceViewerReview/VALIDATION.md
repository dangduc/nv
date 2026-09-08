# Source and viewer validation

Validated on September 8, 2026, on macOS 26.5.2 with Xcode 26.6 and the macOS 26.5 SDK.
The Development app targets Intel and macOS 10.13. It ran under Rosetta.

## Delivered behavior

Source is the default mode. New notes use Plain Text syntax.
Markdown, Textile, and HTML viewers occupy the same body area below the notes list.
Tree-sitter highlights Markdown, HTML, and JSON through temporary layout attributes.
Syntax metadata stays in the local library and does not enter Simplenote requests.

The implementation removes rich-text editing, import, storage, and export support.
It also removes detached previews, sticky previews, sharing, custom templates, and TaskPaper preprocessing.
Text import and source export preserve characters, line endings, encoding, BOM, and original bytes where possible.
Original bytes remain inside encrypted note archives. Pending encoding conversions survive reopening.

## Results

| Check | Result |
| --- | --- |
| Development build | Clean build passed; the final incremental build passed after integration fixes. |
| Multiple-window suite | 48 checks passed across initial launch and relaunch. |
| Aggregate regression suite | All 18 groups passed with exit 0. |
| Source highlighting | 328 checks passed, including laid-out shortening and stale capture invalidation. |
| Source storage | 113 checks passed, including actual writes, export, archive reopen, and conversion retry. |
| Renderer | 90 checks passed for immutable requests, conversion, failures, limits, and cancellation. |
| Inline WK viewer | 104 checks passed. A listening resource server received zero requests. |
| Source workflow | 70 checks passed; the artifact run passed 74 including screenshot capture. |
| Native UI / controls / rendering | 82 / 95 / 438 checks passed. |
| Preview lifetime | 19 Source-only checks and 31 rendered checks passed. |
| Editing / selections / fonts | 52 / 31 / 36 checks passed. |
| Snapshot diff | All 36,136 cases passed. The production diff helper is unchanged. |
| Negative controls | Ownership, selection mapping, restoration, and the new highlight lifecycle checks reject their intended mutations. |
| CI unit tests | All 14 tests passed. |
| Packaged application | Archive validation passed, including four syntax queries and distribution notices. |
| Project and resources | No missing local Xcode references. Plists and all six localized menus parse. Dependency hashes match the manifest. |

The desktop suites used copied apps, isolated settings, and disposable notes.
The [source screenshot](../../docs/screenshots/source-editor.png) and [preview screenshot](../../docs/screenshots/readonly-viewer.png) show the native controls without pixel changes.
Visual inspection confirmed readable source highlighting, the inline preview, and the notes list above both modes.

## Reproduction

Use the Development build command in [AGENTS.md](../../AGENTS.md), then run:

```sh
python3 Tests/run-multiple-windows-tests.py
python3 Tests/run-regression-tests.py
python3 Tests/Regression/selections/run-negative-control.py
python3 -B -m unittest discover -s Tests/CI -v
```

The archive check is `.github/scripts/check-app-archive.py <app-archive.zip>`.
The main local logs are `build/source-viewer-final-build.log`, `build/source-viewer-windows.log`, and `build/source-viewer-regressions-final.log`.
The `source-workflow` suite can capture screenshots through `NV_UI_ARTIFACTS`.

## Limits

No macOS 10.13 runtime or live Simplenote service was tested.
Source fidelity through the existing Simplenote service is outside this local-source contract.
Preview printing requires macOS 11 or later. It was not sent to a physical printer.
External editor applications were not launched.

The parser worker has size, query, and time limits; notes that exceed them remain editable with plain display.
The measurements in [source-highlighting](../Regression/source-highlighting/README.md) exclude end-to-end typing and painting latency.
Viewer transitions use current DOM scroll positions with a 0.5-second cached fallback for missing replies.
Synchronous application termination can use the last cached viewer position.

Existing rich-text formatting and attachments have no preservation guarantee.
Managed native payload storage, Quick Look, injected languages, and structural source tools remain future work.
