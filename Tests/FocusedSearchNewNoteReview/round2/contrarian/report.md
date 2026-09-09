# Round 2: contrarian focus review

No actionable findings in application commit `504f303` against `b289ba3`.

This review cross-read all five round 1 reports and executable probes.
It also examined the available round 2 Ousterhout, Luu, and Torvalds reports and probes.
Their conclusions remain supported within their stated limits.
The round 2 challenge tests focus precision, rather than repeating the round 1 stale-query mutation.

The key-window condition at `Sources/Browser/AppController_Search.m:15` has a concrete purpose.
An inactive browser can retain its Search field editor and keep that editor as its window's first responder.
That does not give Search keyboard focus.
`newNote:` uses the complete focus predicate before capturing its title (`Sources/Browser/AppController_BrowserUI.m:319`).

## Executable evidence

The production app passed **16 assertions**, including four library and activation checks (`output.txt`, exit 0).
The probe uses two browser windows sharing a disposable library.

1. Leave populated Search in the first browser, then activate the second browser.
2. Edit the original note's title in the second browser while both Search fields retain text.
3. Verify that the inactive browser retains a Search editor, while the key browser owns a metadata editor.
4. Dispatch native Command-N. It creates a default-titled note in the key browser and commits the original metadata.
5. Verify that the inactive browser retains its original selection and query.
6. Explicitly call `newNote:` on that inactive browser to isolate the action's own focus guard.
7. Verify a separate, empty, default-titled note and an unchanged peer selection.

The negative control removes only the key-window condition from `searchFieldHasFocus` around step 6.
It passes the native menu and ownership assertions, then fails the inactive-editor title assertion.
`negative-control.txt` records the expected exit 1.
The mutation exists only in the disposable process and is restored before the assertion.

```sh
python3 Tests/ViewControlsReview/run-probe.py --probe Tests/FocusedSearchNewNoteReview/round2/contrarian/probe.inc
NV_CONTRARIAN_NO_KEY_CHECK=1 python3 Tests/ViewControlsReview/run-probe.py --probe Tests/FocusedSearchNewNoteReview/round2/contrarian/probe.inc
```

## Limits

Step 6 is a synthetic direct action to an inactive browser. Normal Command-N routes to the active browser.
The negative control proves the action's defensive focus boundary; it does not establish a normal keyboard path to the inactive browser.
The native menu case uses its key-equivalent API rather than a hardware key event.
This round does not repeat persistence, asynchronous completion schedules, input methods, or broad desktop suites.

The existing runner serializes GUI access through `build/pr-review/gui.lock` and isolates app preferences and notes.
Environment: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), Intel app through Rosetta.
Executable SHA-256: `ffd2506757bfb23cfc26450ce1a736a578babd22af606a313427a6db7e399c43`.
No production files changed during this review.
