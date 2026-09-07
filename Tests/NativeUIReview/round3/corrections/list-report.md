# R3-01 correction: rendered list acceptance

The native UI acceptance fixture now rejects removal of the list's forced Aqua appearance. The current app passed the corrected fixture. The original review fault failed the new background assertion.

The correction changes only test code and documentation. It preserves the existing appearance, body, metadata, search, and layout checks. The fixture also explicitly suppresses sync startup.

The existing appearance loop now contains three populated notes with native alternating rows. A helper samples two unselected row parities under Aqua and Dark Aqua. Each sample requires an opaque pale background and visible dark title glyph pixels.

The helper captures the window content view around each row. Thus, AppKit composites translucent native row fills over the actual containing content. It does not substitute a synthetic white background. It excludes row edges and grid lines from the glyph sample.

This capture method resolves the odd-row transparency limit in the historical review. All baseline row captures contain 14,400 opaque pixels. The faulted Dark Aqua odd-row capture also contains 14,400 opaque pixels.

## Verification

Command, run with sandbox escalation for Cocoa and Rosetta:

```sh
python3 Tests/NativeUIReview/round3/corrections/run-list-canary.py
```

The runner exited with status 0:

```text
list-baseline: 86 passing assertions, 0 mutation activations, fixture passed
list-appearance-fault: 79 passing assertions, 4 mutation activations, fixture failed
FAIL: unselected alternating note rows retain a pale rendered background under the window appearance
LIST CANARY PASSED: current acceptance passes and rejects the activated appearance-removal fault.
```

The baseline count includes four assertions that saved row bitmaps successfully. The fixture contains 82 assertions without bitmap artifacts. Both probe compilations succeeded without compiler output.

| Rendered row | Current app: median brightness | Current app: pale fraction | Dark title pixels |
| --- | --- | --- | --- |
| Aqua, odd | 0.9529 | 92.10% | 200 |
| Aqua, even | 1.0000 | 92.47% | 181 |
| Dark Aqua, odd | 0.9529 | 92.10% | 200 |
| Dark Aqua, even | 1.0000 | 92.47% | 181 |

The faulted app passed both Aqua row checks. Its Dark Aqua odd-row median brightness fell to 0.2118, with a pale fraction of 1.69%. The capture remained fully opaque. The intended background assertion then failed.

Visual inspection of the saved odd-row images showed dark title text on a pale baseline row. The faulted row showed light title text on a dark background.

The fixture requires more than 99% opaque pixels, median brightness above 0.85, and a pale fraction above 70%. It then requires more than ten dark title pixels. The correction retains the thresholds from the positive pixel probe and adds the opacity requirement.

## Provenance and isolation

The source HEAD was `d7a3ef6a740b4f85758f11bc411004b64b402c6f`, with the correction present as uncommitted test changes. `provenance.json` records hashes of the exact test sources and executable. The runner compared those hashes before and after both runs. They stayed unchanged.

The executable SHA-256 was `f9d0a299a852c80fae0574722776d5e732031fec6f4c328861e57d74d9d00228`. The app was unchanged from the review baseline. The host ran macOS 13.7.8 (22H730) and Xcode 15.2 (15C500b), with x86_64 execution under Rosetta.

Each run used a copied app, temporary notes and support files, and a unique preference domain. The runner held `build/pr-review/gui.lock` and used Launch Services with a 90-second timeout. Sync startup and external editor initialization were disabled. Cleanup removed temporary app files and preferences.

`list-baseline.txt` and `list-appearance-fault.txt` contain the full app output. `results.json` records the case results. The corresponding `*-pixels` directories contain the captured rows and window snapshots.

The historical R3 report and captures remain unchanged under `Tests/NativeUIReview/round3/test_contrarian/`. Its passing faulted-acceptance result describes source `0afeb038`. The correction runner demonstrates that the current acceptance fixture rejects the same fault.

The root task owns full regression, multiple-window, and full-screen verification. This correction performed the requested bounded baseline and fault pair. No production build or production source changed.
