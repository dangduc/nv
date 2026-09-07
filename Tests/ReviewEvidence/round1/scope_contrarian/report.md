# Round 1: compatibility and scope skeptic

AI review perspective: a contrarian compatibility review. Reviewed commit `30791c582ec54759e213a97680f2e8b21c413953` against base `4c6cf45`.

## P2: Preserve table column widths and order in browser state

Source: `NotesTableView.m:163-164`; replacement persistence at `AppController_MultipleWindows.m:100-114` and `116-147`.

`restoreColumns` now disables Cocoa column autosave. Previously, the table enabled autosave with separate names for its two layouts. The replacement browser state stores frame, layout, sort, query, and scroll positions, but omits column widths and order.

Resize the Title column and drag it after Date Modified. Save the browser state, then restore that state into a fresh browser. The Title width resets from 188 to 253 points. The order resets from `[Date Modified, Title]` to `[Title, Date Modified]`. The saved query survives the same round trip.

This discards an existing customization whenever windows are restored, including app relaunch. Store widths and order in each browser's saved state and restore them after layout configuration. Consider migrating the existing Cocoa table preferences for the initial window.

## Executable evidence

```sh
python3 Tests/ReviewEvidence/round1/scope_contrarian/run-probes.py
```

The runner compiles an injected Cocoa harness and executes production `browserWindowState` and `restoreBrowserWindowState:`. It copies the built app and uses temporary notes plus a random preferences domain. A shared file lock serializes GUI probes. Run outside the restrictive process sandbox so Rosetta can launch.

Observed on macOS 13.7.8 arm64 with the existing Development x86_64 build:

```text
column=Title original-width=253.0 saved-width=188.0 restored-width=253.0
saved-order=(Date Modified, Title)
restored-order=(Title, Date Modified)
SCOPE CONTRARIAN ROUND 1 COMPLETED (6 checks)
```

This is a defect reproducer: two assertions require the current incorrect behavior. Convert those assertions to preservation checks after the fix.

## Coverage without another finding

The probe confirms that frame and sort fields exist and that a nonempty query survives restoration. Source inspection found that label-filter forwarding has no active UI caller: the legacy tags branch is inside `#if 0`. I excluded that apparent issue. Mixed quoted-search behavior differs from the old parser, but I did not establish a harmful user-visible failure or report it as a defect.
