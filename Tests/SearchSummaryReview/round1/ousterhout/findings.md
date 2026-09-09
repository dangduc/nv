# Round 1: design and complexity review

Perspective: John Ousterhout's emphasis on simple interfaces and explicit state. This review does not represent him.

Production checkpoint: `72c668cc5329ce6e48850377b35ec7d6d5b27d5b`, compared with `4624b3d`. The run used head `60a3c45a130d179ab671cf770e71afcbfb580649`, which contains the same production source.

## Findings

No introduced actionable defect found within the reviewed method.

`updateSearchAffordance` derives status visibility and list height from one local condition. Completed results therefore remove both the summary and its reserved space. The method clears the previous status text and both tooltips on completion.

The change adds no controller state, ownership edge, or asynchronous work. It also removes the display dependency on `distinctResultNoteCount`. The existing `resultCount` dependency still controls zero-result note creation.

Relevant locations are `Sources/Browser/AppController_BrowserUI.m:295`, `:299`, `:302`, and `:307`.

## Executable evidence

Run this command from the repository root in an active desktop session:

```sh
python3 Tests/SearchSummaryReview/round1/ousterhout/run.py
```

The runner extracts the exact production method. It compiles that method with native AppKit controls and an immutable session double. Native runs share `build/pr-review/gui.lock`. The probe opens no note library.

| Case | Result |
| --- | --- |
| Production method | 157 assertions passed, exit 0 |
| Exact old method from `4624b3d` | 8 assertions passed, then the hidden-summary assertion failed, exit 1 |

The state sequence runs at list heights of 0, 8, 24, and 220 points, with a nonzero bounds origin. It covers delayed search, completion, failure, recovery, search before the delay, zero results, Exact mode, and an empty query.

Assertions cover status visibility, text, both tooltips, list geometry, Create and Retry actions, and stable control identities. A second fixture retains its error state throughout all transitions. The production method makes zero calls to `distinctResultNoteCount`.

## Source record and limits

The source and header hashes match before and after both runs. The output record is `build/SearchSummaryReview/round1/ousterhout/results.json`. It contains source hashes, extracted-method hashes, probe hashes, exit codes, and assertion counts. Compiler and run logs remain in the adjacent variant directories.

The source hash is `45b01fcb17f0df40c58689424053b9d221917f302571ab21ecb7afb40dc9e104`. The extracted production method hash is `e26403ef16a379d5012107ee4deac0786595c1f0910c78b392fbc8dc0a2d4cbf`.

The probe ran as arm64 on macOS 26.5.2 (25F84), with Xcode 26.6 (17F113). It exercises native control behavior and explicit session states. It does not exercise the real search worker, timer delivery, window layout notifications, or Intel application startup.

No production change requested by this review.
