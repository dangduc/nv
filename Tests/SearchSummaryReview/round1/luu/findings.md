# Round 1 — measured search-list space

Perspective: Dan Luu's emphasis on measured behavior. This report does not speak for him.

No actionable finding in the changed search affordance or list dimensions.
The review compares production checkpoint `72c668cc5329ce6e48850377b35ec7d6d5b27d5b` with base `4624b3daf2e95a44c578d9895f65890051ed6702` for PR #11.
The measured checkout was `60a3c45a130d179ab671cf770e71afcbfb580649`.
The production source remained unchanged throughout the comparison.

The new probe compiles the complete `updateSearchAffordance` method from each revision into a native ARM64 AppKit fixture.
It uses real `NSScrollView`, `NSTableView`, status text, and button views.
A controlled session output supplies the query, mode, rows, pending state, and error.
No notes library opens.
The runner holds `build/pr-review/gui.lock` during each fixture run.

From an active desktop session, run:

```sh
python3 Tests/SearchSummaryReview/round1/luu/run.py
```

All 40 production cases passed on macOS 26.5.2 (25F84), with Xcode 26.6 (17F113).
The same fixture also produced 40 base observations and 40 negative-control observations.
Ten session states each used these list-pane sizes: 480 × 84, 780 × 180, 1,200 × 320, and 480 × 84 points.
The final size repeats the minimum size after expansion.

The following table shows the 180-point pane.
The other sizes produced the same difference in reserved space.

| Session state | Base list height | New list height | New status text |
| --- | --- | --- | --- |
| Empty query, Fuzzy or Exact | 180 | 180 | Empty |
| Completed fuzzy results, including duplicates | 156 | 180 | Empty |
| Completed Exact results | 180 | 180 | Empty |
| Zero fuzzy results | 156 | 180 | Empty |
| Zero Exact results | 180 | 180 | Empty |
| Fuzzy search before the progress delay | 156 | 180 | Empty |
| Fuzzy search after the progress delay | 156 | 156 | Searching… |
| Fuzzy completion after delayed progress | 156 | 180 | Empty |
| Fuzzy error | 156 | 156 | Search worker unavailable |

The native clip view gained the same 24 points as its enclosing scroll view in each changed state.
At pane heights of 84, 180, and 320 points, completed fuzzy searches now use all 84, 180, and 320 points.
The old method used 60, 156, and 296 points.
Visible progress and error text remained above the list, without overlap.

The duplicate-results fixture contains six rows for four note identities.
The completion fixture contains two rows for one note identity.
Both retain every row and the selected row after each affordance update and resize.
Zero-result states retain the Create action, and the error state retains the visible Retry Search button and its action.
Completed searches clear the search field tooltip and hide the empty status field.

The implementation explains the measured change.
`Sources/Browser/AppController_BrowserUI.m:299` starts with empty status text and sets text only for errors or delayed pending searches.
Line 302 requires both a fuzzy query and nonempty status text before the status strip appears.
Lines 304–306 give the full pane height to the list unless that strip appears.
The method no longer formats the result count, distinct-note count, or ranking explanation.

The independent negative control retains the new text behavior but restores the old 24-point reservation for every nonempty fuzzy query.
It failed 16 geometry cases: duplicate results, zero results, silent pending search, and completion, each at four sizes.
Its status, button, and row-selection assertions still passed.
The base method also failed 16 cases against the new contract, as expected.

An initial attempt included an invalid Exact-mode asynchronous-error state.
That state failed four assertions, one at each pane size.
`Sources/Browser/NVBrowserSession.m:198` clears the fuzzy error during invalidation.
Lines 209–213 refilter after a mode change, and normal Exact filtering has no asynchronous fuzzy error result.
The corrected fixture excludes this unsupported state.
Its original outputs remain under `build/SearchSummaryReview/round1/luu/initial-unreachable-state/`.
This was a fixture-model correction, not a production defect.

The session outputs and progress-delay flag are controlled inputs.
This probe does not measure search scoring, result publication, actual timer latency, or the application resize callback path.
It does not establish a frame-rate improvement, saved computation time, or behavior on older macOS versions.
The fixture uses native AppKit views but excludes the full browser controller, toolbar, and editor.

Production source SHA-256 before and after: `45b01fcb17f0df40c58689424053b9d221917f302571ab21ecb7afb40dc9e104`.
Extracted production method SHA-256: `e26403ef16a379d5012107ee4deac0786595c1f0910c78b392fbc8dc0a2d4cbf`.
Extracted base method SHA-256: `f1b2b503390159d766ceab8fd6c1f0ab530bbb684057df3a668e42654ef6c293`.
The production fixture executable retained SHA-256 `c2538d660e54e347df6bfee95e999edd5ca10932aaa76f80c31719bf5b4145e1` before and after its run.

Raw dimensions, status text, assertions, compiler logs, and all three executable hashes are in `build/SearchSummaryReview/round1/luu/`.
The runner writes one `result.json` per variant and a combined `summary.json`.
No production files, commits, or PR comments changed during this review.
