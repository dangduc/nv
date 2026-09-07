# Browser search regression tests

Run on macOS with Xcode:

```sh
python3 Tests/Regression/search/run.py
```

The runner compiles `NVBrowserSession.m` with in-memory model doubles. It creates no app windows and does not open a notes library.

The 347 checks cover candidate access counts, independent browsers, quoted phrases, separators, case changes, Unicode normalization, sorting, edits, additions, deletions, and pinned rows. They also check invalidation when a UI refresh is deferred.

The suite compares 324 query transitions with fresh searches. Performance assertions use access counts instead of elapsed time.

To confirm that the suite detects the original regression:

```sh
python3 Tests/Regression/search/run.py --source-ref 30791c5
```

That command must fail at `zero-result refinement reads no note contents`. The historical review probe remains in `Tests/ReviewEvidence/round1/luu/`.
