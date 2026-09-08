# Joined capture correction

Addresses PR comment [3956760254](https://github.com/fastducduc/nv/pull/4#discussion_r3956760254).

Each joined caller now keeps its own Find query and other non-scroll state.
It receives the pending document's fallback offsets and shares that read's exact result and deadline.
Returning before completion adopts the latest joined caller's cache.
Completion still updates only scroll offsets in the provider's current state.

The early-return case was checked during the correction.
The callback-only change still failed when A returned before the shared read completed.
`run-return.py` extends the original provider history with that ordering, without changing the historical probe.
It failed at `return before reply adopts the latest joined caller's query` before the entry-state correction.

## Validation

All commands ran on macOS 26.5.2 with Xcode 26.6 and Intel binaries under Rosetta.

| Command | Result |
| --- | --- |
| `python3 Tests/SourceViewerReview/round3/ousterhout/run.py` | 40 checks; joined callback and provider both retain `newer query`. |
| `python3 Tests/SourceViewerReview/round3/ousterhout/run-return.py` | 41 checks, including return before reply. |
| `python3 Tests/Regression/source-viewers/run-viewer.py` | 207 checks and remote-resource fixture check pass. |
| `python3 Tests/SourceViewerReview/round3/ousterhout/run-browser.py` | 11 checks; browser saves and restores `newer`, with Source scroll 280 and Preview scroll 420. |
| Source workflow within `python3 Tests/run-regression-tests.py` | 130 checks pass in `build/review-complete-regressions.log`. |
| `python3 Tests/Regression/source-workflow/run.py` after fixture correction | 136 checks pass twice, in `build/round3-viewer-workflow-final.log` and `build/round3-viewer-workflow-final-repeat.log`. |
| `python3 Tests/SourceViewerReview/round3/ousterhout/run-queued-refresh.py` | 137 checks; all six histories retry after a deliberately queued refresh during native inspection. |

The permanent viewer suite gives three callers distinct queries.
It checks exact replies, timeout, close, explicit restoration, identity, and once-only completion.
The new query assertion failed against the original code before the correction.

The permanent browser suite uses native Find and actual window-state serialization.
It checks save, Find change, same-note refresh, departure, and return with exact reply, timeout, and return before reply.
Saved browser state, the native Find field, provider state, and scroll positions must agree.

Initial workflow runs failed scheduling preconditions before those checks completed.
The affected histories inspected WebKit through a helper that pumps the run loop.
A queued refresh could start during that inspection, before the controlled capture began.
One run failed the new request-count precondition; other runs failed an existing rapid-return precondition.

Both history loops now share bounded document preparation.
It waits for loaded Preview and no prior captures, restores the cache, then reads the document base and scroll together.
After that asynchronous boundary, it verifies the current document identity, readiness, and absence of earlier captures.
It retries up to four times if a refresh interrupted preparation.
The six new setup assertions raise the workflow count from 130 to 136.
Exact replies, timeouts, early returns, queries, and scroll assertions remain in place.

The final workflow passed twice after this fixture correction.
The queued-refresh control confirms that every rapid-return and joined-query history retries preparation when the refresh arrives during native inspection.
The source-based probes also passed independently.
No macOS 10.13 runtime was tested.
