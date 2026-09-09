# Round 2: cancellation ownership

The Ousterhout-perspective subagent found one actionable lifecycle defect. This report consolidates its completed evidence and source inspection.

**[P2] Release canceled browser ownership on the main thread.**

`NVSearchService` cancellation sets flags and removes search/position requests without first releasing their completions. Queued worker blocks can keep those requests alive. Their callbacks retain `NVBrowserSession`, so disposal on the worker can release the last session reference there. The session destructor calls the service's main-thread-only cancellation API.

The fixture uses the production browser session, search service, query, corpus, and matcher. It holds the serial worker queue, submits pending work, then performs the controller teardown sequence: clear the session delegate and release the session. This sequence appears in `AppController` teardown and browser library replacement. The fixture's queue gate controls timing; it does not replace those production lifecycle methods.

The recorded native and ASan/UBSan runs both show:

| Pending channel | Session disposal | Result |
| --- | --- | --- |
| Literal ranges | Main thread, before worker resumes | Pass |
| Search | Worker thread | Main-thread ownership assertion |
| Positions | Worker thread | Main-thread ownership assertion |

The relevant source is `NVSearchService.m` cancellation methods and queued position work; `NVBrowserSession.m` invalidation/destruction; and `AppController.m` destruction. The JSON records contain exact source hashes. The inspected working tree was based on `2c9a11b`.

The completed commands were:

```sh
python3 Tests/FuzzySearch/Review/round-2/ousterhout/run-lifetime.py
python3 Tests/FuzzySearch/Review/round-2/ousterhout/run-lifetime.py --sanitize
python3 Tests/FuzzySearch/Review/round-2/ousterhout/run-lifetime.py --repair-control
```

The test-only repair control releases canceled completion references earlier. It repairs the search case, but the position case still fails. This control is incomplete and is not a production fix. Position worker blocks also capture the owner for a later main-queue guard; fixing only completion release is insufficient.

No full-app close or library-switch execution is claimed. All recorded processes are arm64, on macOS 26.5.2 with Xcode 26.6. The complete controller and disk-backed library are outside the fixture. The review did not complete further broad ownership cases. The production fix must cover all cancellation entry points and verify main-thread disposal without requiring worker completion.
