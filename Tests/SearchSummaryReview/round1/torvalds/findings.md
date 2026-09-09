# Round 1: search status compatibility and actions

No actionable defect emerged from this focused review. Severity: none.

This review uses a correctness and compatibility perspective inspired by Linus Torvalds.
It does not represent his identity, review, or endorsement.

The reviewed change is [PR 11](https://github.com/dangduc/nv/pull/11), production checkpoint `72c668cc5329ce6e48850377b35ec7d6d5b27d5b`, against base `4624b3d`.
The run started at head `60a3c45a130d179ab671cf770e71afcbfb580649` after another evidence commit.
All three inspected production files matched the checkpoint before and after execution.

## New executable evidence

Run from the repository root with authorized AppKit desktop access:

```sh
python3 Tests/SearchSummaryReview/round1/torvalds/run.py
```

The runner extracts three complete, unchanged method bodies from production:

- `updateSearchAffordance` from `Sources/Browser/AppController_BrowserUI.m:291`.
- `createNoteFromSearch:` from `Sources/Browser/AppController_BrowserUI.m:330`.
- `retrySearch:` from `Sources/Browser/AppController_Search.m:53`.

The fixture supplies a typed session and real AppKit controls.
It uses the production methods for status updates and Create/Retry dispatch.
The lower-level creation and refilter operations record calls instead of changing notes.
Both executions hold the shared `build/pr-review/gui.lock`.

The production probe passed **91 assertions across eight states** on macOS 26.5.2 (25F84), using Xcode 26.6 (17F113).

| State | Verified behavior |
| --- | --- |
| Fuzzy failure | Error text and both status tooltips agree. Retry is visible, enabled, and correctly targeted. |
| Retry before delay | Retry cancels intents and requests one refilter. The error tooltips clear, and the list fills its container. |
| Pending after delay | Searching appears, reserves 24 points, and leaves Create hidden. |
| Completed fuzzy matches | Status text and tooltips clear. The list fills its container, and Create stays hidden. |
| Completed fuzzy zero | Create appears with the Unicode query in its title and tooltip. Clicking forwards the original sender once. |
| Completed exact matches | Status stays hidden, the list fills its container, and Create stays hidden. |
| Completed exact zero | Create remains available with its existing handler. |
| Empty query | Status and tooltips remain empty. Create stays hidden, and the result count is not queried. |

Pending and failed states never read an unavailable result count.
No state reads the distinct-note count formerly used only by the summary.
Each state checks the button target, selector, handler availability, enabled state, and visibility.
Create does not dispatch Retry; Retry does not dispatch creation.

The extracted methods also passed an Intel syntax and API-availability compile targeting macOS 10.13.
The compile uses `-Wall -Werror -Werror=unguarded-availability -Werror=unguarded-availability-new` with manual memory management.
Both native executables compiled with the same warning settings.

## Negative control

The generated negative variant changes one setter to preserve the old search-field tooltip when the new status is empty.
It first passes the complete error-display and Retry-dispatch checks.
It then fails at `retry before delay: field tooltip`, after **16 successful assertions**.

The negative process exits with status 1.
The runner requires that exact failure and returns success only when production also passes.
This control verifies detection of a stale error tooltip during recovery.
It changes only generated code under `build/`.

## Source records

| Input | SHA-256 |
| --- | --- |
| `AppController_BrowserUI.m` | `45b01fcb17f0df40c58689424053b9d221917f302571ab21ecb7afb40dc9e104` |
| `AppController_Search.m` | `c9140868ba8ff918e47f420bf7a33efed22232ec4bdcf77be075fbbad92f6a68` |
| `NVBrowserSession.m` | `2ec178fde253541204b26e36c3bfce018aacb17fe0469ceecd17bfa9ce91e170` |
| Extracted method bodies | `7a571db3459204eda5faf5c96b3fee808e59f32f61e4581aa031ad7d54667c7b` |
| New `probe.m.in` | `716a5c6c04113016d450d2b1adc61f8b295dc2e5b1752cf7479ace16ab4e545f` |

Generated sources, compiler logs, execution logs, and `results.json` reside in `build/SearchSummaryReview/round1/torvalds/`.
The JSON records full commands, return codes, assertion counts, and source hashes before and after execution.
It reports no changed inputs.

## Limits

The session is a fixture, so this test does not establish asynchronous service behavior, search ranking, or note persistence.
The controls are created directly; this probe does not establish nib wiring or full application lifecycle behavior.
The delay flag is set directly, so the probe does not measure the 100-millisecond timer.
The Intel check establishes SDK declaration availability, not runtime compatibility with macOS 10.13.
The Unicode label case does not establish translated resource coverage.

The inspected diff changes only summary construction and the condition for reserved status space.
It leaves the action methods and session contracts unchanged.
This review adds only its new fixture, runner, and report. It makes no production edits or commits.
