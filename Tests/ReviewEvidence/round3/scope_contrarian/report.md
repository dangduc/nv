# Round 3: compatibility and scope skeptic

AI review perspective: a contrarian compatibility review. Reviewed source and the Development app at `3502c7c49660cb4750a9de7f02fedd7e6fd314e8`.

## Result

No new actionable finding in this review's scope. The new Cocoa probe completed 144 assertions across a sequence of menu actions and state restores. This count includes repeated visibility and menu-state invariants for three windows.

## Executable evidence

```sh
python3 Tests/ReviewEvidence/round3/scope_contrarian/run-probes.py
```

Observed on macOS 13.7.8 arm64 with the x86_64 Development app:

```text
SCOPE CONTRARIAN ROUND 3 COMPLETED (144 checks)
```

The runner copies the app, assigns a random preferences domain, creates temporary notes, and holds the shared GUI lock. Run outside the restrictive process sandbox so Rosetta can launch.

## Coverage

- Dispatches production-generated column menu items through `NSApplication` and the application coordinator after changing the active browser.
- Hides and shows Date Modified, Tags, and Date Created across two vertical browsers and one horizontal browser.
- Checks each table's visible columns against global preferences, rejects duplicates, and checks the generated menu states after each operation.
- Selects each affected sort column before hiding it and verifies fallback in all three browsers.
- Confirms that different queries and Title widths survive these shared preference changes.
- Restores an old state without column settings and with an unknown sort identifier. Query restoration and the Title fallback pass.
- Restores a current vertical state over a horizontal browser and checks the resulting column sets.

These checks extend the round-two visibility correction to coordinator routing, multiple column types, and restoration after the changes.

## Limits

The directly launched disposable app remains inactive and reports no main window in this test environment. The harness therefore delivers the production `windowDidBecomeMain:` delegate callback before dispatching each command. This tests the coordinator and its targets; it does not verify macOS focus delivery through physical clicks. Initial attempts to rely on activation requests failed that harness precondition and were not treated as product defects.

Source inspection also showed that the sorting menu intentionally lists hidden columns. I did not report restoring a known hidden sort key as an invalid-column defect.
