# Round 1: Kingsbury perspective

No actionable defect found in these bounded state-consistency histories.
This review uses a Kyle Kingsbury-inspired perspective. It makes no identity or endorsement claim.

Reviewed [PR #11](https://github.com/dangduc/nv/pull/11), production `72c668cc5329ce6e48850377b35ec7d6d5b27d5b` against `4624b3d`.
The starting review HEAD was `60a3c45a130d179ab671cf770e71afcbfb580649`.
Other review records advanced HEAD during execution. The exact execution HEAD appears in [results.json](results.json).
All six recorded production files matched the reviewed production commit and remained unchanged throughout both launches.

## Executable evidence

Run from the repository root with desktop access:

```sh
python3 Tests/SearchSummaryReview/round1/kingsbury/run.py
```

The normal copied-application run passed **101 checks** across three histories with three disposable notes.
The model declares the query, mode, selected document, result currency, status text, and Retry availability after each explicit event.
It also specifies the 24-point allocation only while transient status is visible.
Expected values do not come from the status UI under test.

1. Pending to completed: the immediate pending state has no status text or reserved strip.
   The real delayed-progress timer shows `Searching…` while callback delivery waits.
   Completion clears the text and both tooltips, hides the label, and returns the full list area.
   A later explicit progress callback cannot restore the removed summary or change the query and selection.
2. Error to Retry to completed: an injected callback error shows its text, reserves the strip, and exposes the real Retry Search button.
   Return in that failed state creates no note. Clicking Retry clears the error and starts a new request for the same query.
   Failure and success callbacks from the old request cannot alter the retry state.
   Delayed progress still works during retry. The current completion selects the requested note and clears all transient status.
3. Mode replacement: a fuzzy search waits with visible progress, then a newer Exact query selects another note.
   Obsolete failure, success, and progress callbacks cannot change the new query, mode, selection, tooltips, or full list allocation.

The tests run the actual Intel application, AppKit controls, browser controller, session, service, model, and native matcher.
A runtime wrapper retains completed service callbacks and delivers them at specified main-thread boundaries.
Only the error path injects a synthetic error. Matching and request identity remain production behavior.

## Negative control

The separate control wraps `updateSearchAffordance` in the copied app.
After successful fuzzy completion, it restores a visible completed summary and the old 24-point strip.
The control passes the initial Exact state, immediate pending state, and delayed-progress checks.
It then fails after **31 passing checks** at the first completed-state visibility assertion:

```text
FAIL: status visibility follows the independent event model
```

The negative process exits 1. The review runner exits 0 only when the normal history succeeds and this exact failure occurs.

## Source identity and results

[results.json](results.json) records exact commands, environment overrides, exit codes, counts, and fixture hashes.
It also records all six production hashes before and after execution and checks their equality with the reviewed commit.

| Input | Stable SHA-256 |
| --- | --- |
| `Sources/Browser/AppController_BrowserUI.m` | `45b01fcb17f0df40c58689424053b9d221917f302571ab21ecb7afb40dc9e104` |
| Built `nvALT` executable | `efc6fce32c2647e78909efe32d699737a58b3987cdc8b0ddb5fde753d67fdb99` |

The executable hash also matched before and after the normal and negative runs.
The host ran macOS 26.5.2 (25F84), Xcode 26.6 (17F113), and the Intel app under Rosetta.
The shared runner serialized both launches with `build/pr-review/gui.lock` and isolated notes, application support, and preferences.
Full ignored logs are `build/SearchSummaryReview/round1/kingsbury/history.log` and `old-summary.log` in that directory.

## Limits

This is a small set of controlled histories on one macOS release, not proof for all event schedules or supported releases.
The injected error tests the production browser error path without a real filesystem or matcher failure.
Old callbacks are replayed to check receiving generation fences. The test does not claim that the service normally completes a request twice.
The late progress callback directly invokes the production handler after completion.
The tests use native method and button calls rather than physical input events.
They do not cover full-screen layout, tiny windows, localization, or process restoration.
They do not rerun unrelated suites or the documented baseline Undo and activation failures.

This review created only its assigned evidence files. It made no production edits, commits, or PR comments.
