Round 2 review: selected rich text rendering

This AI review applies a Dan Luu-inspired measurement perspective. Dan Luu did not participate.

No new actionable finding arose from this probe. The corrected app and the pre-UI baseline each passed 98 checks. All 16 matching PNG captures contain identical bytes.

The reviewed source is `12936fed78e1d98ac646bb88b51e009609ad505e`. The baseline source is `116daff`. The host used macOS 13.7.8 (22H730), Xcode 15.2 (15C500b), and x86_64 binaries under Rosetta.

| App | Executable SHA-256 |
| --- | --- |
| `build/DerivedData/Build/Products/Development/nvALT.app` | `f9d0a299a852c80fae0574722776d5e732031fec6f4c328861e57d74d9d00228` |
| `build/UIDerivedDataBaseline/Build/Products/Development/nvALT.app` | `f303d00d025a691ee5a5975d8a60a255da3e9dd079b58ab22166d9712c74a3e6` |

`LinkingEditor.m:398-411` substitutes the browser foreground through the layout delegate. The existing rendering checks clear selections before capture at `Tests/Regression/native-rendering/probes.m:228-232`. This probe adds evidence for active selections across rich attributes and URL boundaries.

The probe types one synthetic note through the body editor. It applies the native Bold, Italic, and Strikethrough actions to separate lines. A fourth line contains a typed URL. The probe checks the resulting font traits, strikethrough attribute, and link attribute before capture.

The four cases combine light and dark editor colors with clickable URLs on and off. Each case selects the complete body. Each capture checks the key window, first responder, selected range, visible glyph bounds, foreground pixels, and selection background pixels.

Expected result: each selected run contains readable foreground pixels and selection pixels. Font styles and other stored attributes remain intact. The corrected app preserves the complete attributed storage. The baseline changes stored foreground colors, so its comparison excludes only that attribute.

| URL case | Expected foreground pixels | Actual foreground pixels, current / baseline | Actual selection pixels, current / baseline |
| --- | --- | --- | --- |
| Light, clickable off | More than 10 black pixels | 316 / 316 | 1253 / 1253 |
| Light, clickable on | More than 10 link-color pixels | 195 / 195 | 1153 / 1153 |
| Dark, clickable off | More than 10 white pixels | 496 / 496 | 1170 / 1170 |
| Dark, clickable on | More than 10 link-color pixels | 610 / 610 | 1051 / 1051 |

Across all 16 captures, the minimum foreground count was 162. The minimum selection count was 565. Both apps produced these counts.

The exact final commands ran from the repository root:

```sh
python3 Tests/NativeUIReview/round2/luu/run.py --artifacts Tests/NativeUIReview/round2/luu/current > Tests/NativeUIReview/round2/luu/current.log 2>&1
python3 Tests/NativeUIReview/round2/luu/run.py --app build/UIDerivedDataBaseline/Build/Products/Development/nvALT.app --artifacts Tests/NativeUIReview/round2/luu/baseline > Tests/NativeUIReview/round2/luu/baseline.log 2>&1
```

Both commands exited `0`. Both final output lines contain `ROUND2 LUU SELECTION PASSED (98 checks)`.
`current.txt` and `baseline.txt` preserve the complete final log contents. The `current/` and `baseline/` directories contain the PNG captures.

The runner acquires `build/pr-review/gui.lock`. It copies the app, creates a unique defaults domain, and uses temporary notes, support files, and temporary storage. It omits delayed sync actions and external editor initialization. Each app process has a 90-second timeout. The tool calls requested elevated execution for Rosetta.

The fixture explicitly establishes native activation and the custom color scheme. It refreshes editor colors after each clickable-URL change. An initial unsupported Underline action failed its fixture prerequisite. The final probe uses the application's Strikethrough action.

An initial pixel tolerance rejected visible blue links in both apps. The final foreground tolerance matches the existing rendering suite at `0.25`. The final selection tolerance is `0.10`, with a separate minimum distance from the editor background. The logs record actual distances. Matching baseline images support this tolerance choice.

This probe covers one active browser, one synthetic note, and four explicit color cases. It does not measure latency, memory use, inactive selections, printing, or PDF output. It does not establish behavior for every font or color scheme. The probe required no production changes.
