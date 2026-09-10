# Round 2 — Kyle Kingsbury-inspired state and interleaving review

This is an agent review from a state and interleaving perspective. Kyle Kingsbury did not perform this review.

No actionable defect was found in the recorded run. The native AppKit probe passed 57 checks. All six negative controls failed at their intended assertions.

## Tested revision

The run recorded HEAD `5db853c252edf2cb8c81fc10e88f722006f3edb3` on macOS 26.5.2, ARM64. The runner enabled AddressSanitizer and UndefinedBehaviorSanitizer. The positive run exited with status zero and no standard error output.

`manifest.json` preserves the SHA-256 hashes of four production files before and after the run. All four pairs match. Those hashes identify the tested code, regardless of later commits in this shared worktree.

## Evidence and result

`run.py` extracts these production methods without changing their bodies:

- `invalidateSearchHighlights`
- `removeHighlightedTerms`
- `setSearchHighlightRanges:`
- `searchSourceStorageWillProcessEditing:`
- `refreshSearchHighlights`

`probe.m` runs those methods with native `NSTextStorage`, separate layout managers, and copied asynchronous completion blocks. A test service preserves canceled work so the application closures must reject late delivery.

The probe enumerates all 12 legal orders of four events: source edit, search refresh, old completion, and new completion. Each new completion follows its request. An independent model tracks source revision and request identity. Both completion decisions agree with that model in every schedule.

The shared-edit schedule leaves a second character edit open while a nested run loop dispatches pending cleanup. Neither layout receives temporary-attribute writes during that edit. Old callbacks cannot publish during the edit. A callback captured inside the edit is rejected after `endEditing`. A third owner then attaches to the source. Its fresh highlights survive while another peer clears stale backgrounds. All pending states settle after edit processing ends.

The remaining checks cover selection changes, selection returning to the original note, pending search results, no selected row, error completions, and both fuzzy completion stages. A source edit prevents obsolete first-stage work from entering validation. An edit between the two stages prevents publication of the validated old ranges. A current successful callback still publishes.

## Negative controls

Each control changes only the extracted test adapter. Production files remain unchanged.

| Removed guard | Observed failure |
| --- | --- |
| Character-edit generation increment | Old completion disagrees with the revision/request model. |
| Search-refresh generation increment | Old completion disagrees with the revision/request model. |
| Selected row key comparison | A late callback publishes after the selected key changes. |
| Current search-results check | A callback publishes while search results are pending. |
| Dirty-storage cleanup guard | Pending cleanup does not survive the open edit. |
| Dirty-storage publication guard | A callback installs ranges during the open edit. |

The exact outputs are stored in `manifest.json` and the corresponding `.txt` files. `positive.txt` contains the successful run summary.

## Limits

The service, browser session, table selection, and note objects are test adapters. This probe does not test worker cancellation itself or instantiate browser windows. It does not exercise native input methods, pixels, window closure, or the complete note-switch method.

The nested edit is a defensive TextKit schedule. It does not establish that normal application actions switch notes during storage processing. No such unsupported transition is reported as a production defect.

The run used macOS 26.5.2. It does not reproduce the user's exact macOS 13.7.8 crash. This round did not repeat the full window suite or investigate the separate library-switch failure.

The recorded run completed before this report was written. No additional experiment was required to summarize its results.
