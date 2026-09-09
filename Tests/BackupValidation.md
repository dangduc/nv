# Automatic backup validation

Host: macOS 26.5.2 (25F84), Xcode 26.6 (17F113).
Date: September 8, 2026.

Production revision: `8ebbcb511415958f700ca54e4216e6447464d284`.
Round 3 changed review evidence and documentation only.

| Check | Result |
| --- | --- |
| Intel Development build | Passed with the repository build command. |
| Backup filesystem engine | 376 assertions passed. Includes interrupted publication, corruption, retention, ownership, unavailable or replaced destinations, and restore writes. |
| Production backup coordinator | Passed with a fake clock, controlled queues, disposable defaults, and fake library/store services. |
| Native Preferences pane | Passed settings, input checks, stale library edits, action routing, and scrolling error text. The rendered pane was inspected. |
| Native offline archive harness | 72 checks passed with production archive/model code, UI stubs, and a test AES provider. |
| Prepared browser/session teardown | Four call-count checks passed. Three deliberately unsafe mutations failed as expected. |
| Backup store and coordinator static analysis | Passed on arm64 and x86_64. Strict compilation also passed with warnings treated as errors. |
| CI utility tests | All 14 tests passed. |
| Native review regressions | All 20 runners passed together after round 3. Run with `python3 Tests/BackupReview/run.py`. |
| GitHub Intel build | Passed for the production revision above. The master-only tagging job was skipped. |
| Copied-app archive probe | Blocked before application startup by an Intel runtime stall. No desktop assertions ran. |
| Multiple-window suite | No application output before the 180-second timeout. The disposable process group was stopped. |
| Aggregate regression suite | Native backup checks passed. Execution stalled at the copied-app archive probe before startup. The disposable process group was stopped after 180 seconds. |

The full desktop release checks remain incomplete on this host.
The stalled disposable Intel process stayed in a kernel wait after termination signals, as in the earlier resize investigation.
These attempts produced no application assertion failure. They also provide no evidence of successful window or journal integration.
No personal notes were used for these checks.

All 18 reviews are complete. Delegated agents corrected eight distinct findings.
Round 3 found no new actionable issue within its documented scope.
The [review record](BackupReview/README.md) links all PR comments and correction evidence.
Native review coverage includes retention, draft preservation, deletion ownership, retry timing, and stale completion isolation.
It also covers invocation returns, library attachment, restore refusal, and journal recovery through extracted production methods and disposable files.
Each report identifies its fixtures and limits.

The native archive harness substitutes CommonCrypto for the bundled Intel OpenSSL library.
It does not establish compatibility of the shipping crypto binary or the full application lifecycle.
[Archive coverage and measurements](BackupArchive/README.md) record these limits and the capture benchmark.
For 10,000 synthetic notes, archive capture took about 364 ms before primary database checks or disk writes.
The benchmark process reached about 1,000 MiB peak memory. Larger libraries can pause during main-thread capture.

The following commands remain necessary on a host where the Intel app launches:

```sh
python3 Tests/BackupArchive/run.py
python3 Tests/run-multiple-windows-tests.py
python3 Tests/run-regression-tests.py
```

The runtime checks must include actual restore, initialization-failure rollback, encrypted recovery, and continued editing after the library switch.
