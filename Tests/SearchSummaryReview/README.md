# Search summary removal

Completed searches no longer show a result count or the “title matches first” message above the notes list.
The notes list reclaims the 24-point strip, and the search tooltip clears after completion.
Delayed progress and search errors retain their status text. Retry Search and zero-result note creation remain available.

The production change is `72c668c`, based on merged upstream commit `4624b3d`.
It changes only `updateSearchAffordance` in `AppController_BrowserUI.m`.

## Validation

The Development Intel build passed on macOS 26.5.2 (25F84), with Xcode 26.6 (17F113).
The [copied-app probe](app/checks.inc) passed 26 checks, including the optional window render.
It uses disposable notes and the shared desktop-test lock.

```sh
python3 Tests/SearchSummaryReview/app/run.py
```

The probe covers four result rows across three notes, literal-title priority, Exact search, zero-result creation, and search clearing.
The [window render](../../docs/screenshots/search-without-summary.png) shows the actual app with an active query and no summary strip.

The required multiple-window suite still fails after shared-body Undo: index 13 is outside string length 12.
The previous PR reproduced this exception on the unchanged baseline. This change does not alter that code.
Aggregate regressions pass their native search checks, then stop at the copied fuzzy app's active-window assertion.
The complete desktop suites are therefore not green.

## Reviews

Two rounds use the requested Ousterhout, Luu, Torvalds, Kingsbury, and contrarian perspectives.
Each reviewer supplies executable evidence and a deliberate failure control.
Review reports and PR comment links will appear here as each round completes.
