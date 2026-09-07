# Round 2: compatibility and scope skeptic

AI review perspective: a contrarian compatibility review. Reviewed commit `4008592b06c6e634d5e3967f9f4c7d78bad50ef0` against base `4c6cf45`, including fixes since `30791c5`.

## P2: Apply global column visibility changes to every browser

Source: `AppController_MultipleWindows.m:69-73` registers each browser for column changes, but `AppController.m:1037-1041` only reloads rows. `NotesTableView.m:516-520` adds a column without checking whether that browser already displays it.

Open two vertical browser windows. Use the first window's Columns menu to hide Date Modified. Global preferences and the first window hide it, but the second window still displays it. The second window's menu now reports that the displayed column is hidden.

Toggle Date Modified through the second window's menu. It adds the same column object again. The second table now contains `[Title, Date Modified, Date Modified]`; the first table still contains only Title. This follows production-generated menu items and actual table actions.

Synchronize the column set and menu state in each browser when the shared visibility preference changes. Preserve each browser's widths, order, and layout. Guard additions against duplicates, and update a browser's sort selection if its sorted column becomes hidden.

## Executable evidence

```sh
python3 Tests/ReviewEvidence/round2/scope_contrarian/run-probes.py
```

The runner uses the built app at this commit, a copied bundle, temporary notes, a random preferences domain, and the shared GUI lock. Run outside the restrictive process sandbox so Rosetta can launch.

Observed on macOS 13.7.8 arm64, x86_64 Development app:

```text
After hide: global=(Title), first=(Title), second=(Title, Date Modified)
Second menu item state=off despite displayed column
After second toggle: first=(Title), second=(Title, Date Modified, Date Modified)
SCOPE CONTRARIAN ROUND 2 COMPLETED (9 checks)
```

Two assertions reproduce incorrect behavior and must become preservation checks after the fix.

## Prior-fix validation

The new probe also restores a saved 188-point Title column into the second browser. Its width remains 188 points, confirming the round-one persistence correction on this head. The existing 22-check column suite additionally covers separate window settings, layout switches, malformed state, bounds, and missing-field compatibility. The new finding concerns global visibility propagation, which that suite did not exercise through both windows' menus.
