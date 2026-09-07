# Round 3: browser cache and lifetime review

AI review perspective inspired by Dan Luu; not a statement by Dan Luu. Reviewed PR #1 at `3502c7c`, with feature base `4c6cf45` and prior review heads `30791c5` and `4008592`.

## Result

No new actionable finding reproduced. This round exercised preview-cache isolation and deferred browser-session teardown, beyond the query mutation trace from Round 2.

## New executable evidence

```sh
python3 Tests/ReviewEvidence/round3/luu/run.py --canaries
```

The probe compiles the current production `NVBrowserSession.m`. It reuses in-memory fixture definitions and supplies new cache/lifetime scenarios. It creates no app windows or notes directories.

Observed: **208 production checks passed**.

- Across two browser sessions, 1,280 preview requests built 128 preview objects: one per note per browser for 64 notes.
- One hundred resize/invalidation cycles kept the first browser's cache at 64 entries. The second browser retained its existing cached object. The observed 6,530 total builds include 128 initial builds, 6,400 resize builds, and two post-rename builds.
- A library change cleared both caches. Both rebuilt previews contained the renamed title.
- After those cache operations, extending a zero-result query requested zero note contents and zero library snapshots. The Round 1 search fix remains effective in this sequence.
- Sixty-four sessions were released while each had a queued production refresh. Clearing each borrowed delegate followed the `AppController` teardown order. After callback delivery, the sentinels reported 64 destroyed owners, 64 destroyed sessions, 64 destroyed notes, and one destroyed library.

## Sensitivity checks

The runner compiled three mutations in temporary source copies. All failed the corresponding assertion with exit status 1:

| Mutation | Assertion that failed |
| --- | --- |
| Disable preview-cache lookup | Repeated requests reuse the cached objects |
| Omit resize-cache invalidation | Cache entry count remains bounded after resize |
| Omit the browser session's library release | Deferred teardown releases the library and notes |

## Scope and limits

Relevant production paths are `NVBrowserSession.m:77-87`, `168-175`, and `205-237`, plus the teardown ordering in `AppController.m:2165-2166`.

The probe uses title-only previews and synthetic table/column objects; it does not assess text layout or prove that every native resize event calls the invalidation method. The 0.5-second run-loop pump delivers existing 0.2-second deferred callbacks; it is not an editing-latency target. Full application memory use and live sync were not measured. Production files, the shared app, and Git state were unchanged.

Environment: macOS 13.7.8, arm64, Apple clang 15.0.0, optimized native probe build.
