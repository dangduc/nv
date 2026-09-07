# Round 3: test evidence review

This review found one P2 coverage gap for the white note list. The current app passed the pixel baseline. The gap does not establish a current product defect.

The source HEAD was `0afeb03837b94c1a16da211a79c9eaf8dfe51183`. Production code and the tested Development app were unchanged from `12936fed78e1d98ac646bb88b51e009609ad505e`. The host ran macOS 13.7.8 (22H730) and Xcode 15.2 (15C500b), with the x86_64 app under Rosetta.

The executable SHA-256 was `f9d0a299a852c80fae0574722776d5e732031fec6f4c328861e57d74d9d00228`. `provenance.json` records the executable and acceptance source hashes. The hashes stayed unchanged across all four runs.

## P2: Cover the rendered white list during appearance changes

Location: `Tests/Regression/native-ui/checks.inc:146-155`.

The acceptance fixture changes the window appearance and checks the editor background and body foreground. It does not check the rendered note list. Thus, it does not enforce the white-list requirement during the same appearance transition.

A review-only fault removes the explicit Aqua appearance from `notesSubview` after native browser setup. This fault models deletion of `AppController_BrowserUI.m:49`. It preserves other setup and the automatic editor appearance callback.

The unchanged acceptance fixture passed all 68 assertions with this fault. The log records four mutation activations. Therefore, this suite accepts removal of the appearance boundary that keeps the list pale under Dark Aqua.

The separate pixel probe creates six notes and enables the native alternating-row preference. It samples two unselected populated rows under Aqua and Dark Aqua. Native app activation succeeds before the pixel checks.

The unmodified app passed all 13 pixel assertions. Under Dark Aqua, its list and table retained Aqua appearance. Both sampled rows retained pale backgrounds and visible dark title glyphs.

The faulty app passed the Aqua pixel checks. Under Dark Aqua, its list and table inherited Dark Aqua. The pale-background assertion then failed after 11 passing assertions.

The fully opaque second row provides direct evidence of the unwanted rendered change:

| Dark Aqua window, unselected row 2 | Current app | App with the fault |
| --- | --- | --- |
| Opaque pixels | 18,000 | 18,000 |
| Median brightness, range 0 to 1 | 1.000 | 0.110 |
| Fraction of pixels brighter than 0.85 | 94.62% | 1.00% |
| Observed title glyphs in the saved bitmap | Dark on white | Light on dark |

The current row contains 155 dark title pixels. The faulty row contains 221 light title pixels. Visual inspection of both saved bitmaps confirms the background and text change.

The acceptance suite needs rendered list assertions for both row parities under Aqua and Dark Aqua. The removal fault provides a negative control. These assertions can preserve the current white list with pale alternating rows.

## Executable evidence

Command, run with sandbox escalation for Cocoa and Rosetta:

```sh
python3 Tests/NativeUIReview/round3/test_contrarian/run-canaries.py
```

The runner exited with status 0 and recorded these results:

| Case | Passing assertions | Mutation activations | Fixture result |
| --- | --- | --- | --- |
| Unchanged acceptance, current app | 68 | 0 | Passed |
| Unchanged acceptance, fault | 68 | 4 | Passed |
| Pixel probe, current app | 13 | 0 | Passed |
| Pixel probe, fault | 11 | 1 | Failed at the intended background assertion |

The faulted pixel log contains this exact failure:

```text
FAIL: unselected alternating note rows retain a pale background under the window appearance
```

`results.json` contains the case results. The four `.txt` logs contain app output. All four probe compilations succeeded. Each pixel probe emitted one Dark Aqua availability warning against the inherited macOS 10.13 deployment target. The tested macOS 13.7.8 host supplies that API. The `*-compile.txt` files preserve the compiler output.

The saved images that support the finding are:

- `pixels-baseline-pixels/NSAppearanceNameDarkAqua-row-2.png`
- `pixels-fault-pixels/NSAppearanceNameDarkAqua-row-2.png`

`mutations.m:8` defines the single fault. `pixel-checks.inc:27` starts the appearance cases. `pixels.m:10` captures actual table drawing into a bitmap. The pixel assertion requires a median brightness above 0.85 and a pale fraction above 70%.

The runner copies the acceptance probe and checks without byte changes for the first two cases. It substitutes only its own check file for the pixel cases. The same isolation and fault module applies to all four cases.

Each run uses a copied app, temporary notes and support files, and a unique preference domain. The runner holds `build/pr-review/gui.lock` and uses Launch Services with a 90-second timeout. The module explicitly suppresses sync startup. The fixture suppresses external editor initialization. Cleanup removes each temporary directory and preference domain.

Launch Services returned status 0 for all cases. The runner records explicit fixture success or failure markers separately from launcher status.

## Limits

- The finding concerns an acceptance gap. The current app retains the required pale list in these cases.
- The faulty odd-row capture contains native transparency. Its opaque-pixel count does not support a whole-row brightness conclusion. The finding uses the fully opaque second row.
- The captures use AppKit view drawing into bitmaps. They do not establish final desktop compositor output or accessibility contrast compliance.
- The probe uses unselected rows with alternating backgrounds. The separate workflow review covers active and inactive selection.
- This review uses one appearance fault. It does not repeat the full regression suite or full-screen checks.
- No production code, acceptance source, shared app, personal notes, or live services changed.
