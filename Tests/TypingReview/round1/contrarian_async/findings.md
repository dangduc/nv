# Round 1: contrarian review of asynchronous work

Reviewed `b3c2162` against `8dde5e8`. This review challenges the assumption that moving work to a worker also bounds work.

No additional actionable finding was confirmed. The separate link-publication hash-collision finding remains outside this report.

## Executable evidence

Run `python3 Tests/TypingReview/round1/contrarian_async/run.py`.

The probe compiles the production `NVSourceAnalysis.m` and the unchanged production link decorator methods. It pauses the first decorator call with a semaphore. It leaves main-thread requests and completions operational.

All **60 assertions and two negative controls passed**:

- Six sessions request analysis. Five jobs queue behind the paused first job.
- Four sessions receive 10,000 edits each. Each retains one initial snapshot while the worker is blocked.
- A queued session closes and releases its delegate on main before its job runs.
- After the barrier opens, each surviving edited session captures one replacement and publishes generation 10,001 exactly once.
- The unmodified session publishes once. Other sessions' invalidations do not cancel its job.
- Canceled queued jobs skip link extraction. The running job finishes, then discards its canceled result.
- A nil snapshot does not cause a retry loop. Later explicit demand restarts analysis.
- Demand issued from a publication callback receives one subsequent capture and publication.
- Requests after closure do not restart work.

The negative controls modify generated copies of the helper. Publishing canceled results fails the generation assertion. Running canceled link jobs fails the decorator-call assertion.

## Assessment and limits

The scheduler bounds retained snapshots per editing session and coalesces pending requests. The test supports that narrower claim, even with several sessions sharing the serial queue.

It does not establish a runtime bound for one detector or word-count call. Cancellation cannot interrupt either operation after it starts. A long running analysis can delay other sessions until it completes. The semaphore models this ordering; it does not measure a realistic worst-case delay.

The probe tests scheduling without windows or layout managers. It does not cover native menu tracking, IME presentation, teardown through application controllers, or frame latency on macOS 13. No production changes were made during this review.
