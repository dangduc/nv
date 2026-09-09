# Round 3: recovery retry costs and command guards

Dan Luu-inspired review lens. Dan Luu did not author this review.

PR: #8. Production baseline: `8ebbcb511415958f700ca54e4216e6447464d284`.
Host: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), native arm64.

## Result

**No new actionable issue in this bounded review.**

The recovery loop at `Sources/Application/NVApplicationController.m:270` preserves the prepared library through repeated Retry and canceled Quit responses.
The loop performs one exclusive journal open attempt after each response.
It does not repeat archive publication, checkpoint capture, or replacement initialization.
The archive and preparation calls precede the loop at lines 243 and 246.

The exclusive failure path at `Sources/Storage/NotationController.m:457` preserves the competing journal through all 256 responses.
Successful resume clears the preparation flag and restarts storage once at `Sources/Storage/NotationController.m:785`.
The final recovery attempt creates exactly one journal descriptor.

The command guard at `Sources/Application/NVApplicationController.m:503` returns zero bytes for each non-void result in this fixture.
The fixture covers object, BOOL, integer, double, NSRange, and 64-byte struct results, plus void calls.
Both command routes remain blocked at `Sources/Application/NVApplicationController.m:368` and `Sources/Application/NVApplicationController.m:513`.
The normal forwarded command works after recovery.

## New executable evidence

The probe reuses the round 2 Kingsbury collaborators and replaces their scenario in full.
The runner extracts the current production restore, resume, journal initialization, checkpoint, autosave, and command methods without changes.
The journal fixture uses real `open(O_EXCL)`, writes, synchronization, and close operations.
The note model, archive encoder, recovery dialog, application object, and browser collaborators remain fixtures.

The scenario supplies 256 responses, including 63 canceled Quit responses.
The last response deletes the competing journal from the disposable directory.
The next exclusive open succeeds and the restore method returns its original failure.
The selected library remains the original library.

| Measurement | Result |
| --- | ---: |
| Recovery dialog responses | 256 |
| Canceled Quit responses | 63 |
| Original journal open attempts | 257 |
| Repeated checkpoint captures during retry | 0 |
| Restore archive writes | 1 |
| Replacement initialization attempts | 1 |
| Descriptor growth during failed retries | 0 |
| Additional descriptor after successful resume | 1 |
| Peak RSS growth during responses | 2,686,976 bytes |
| Return-shape checks | 1,792 |

The RSS assertion permits less than 16 MiB growth across this scenario.
The reported growth includes the fixture assertions and their Objective-C objects.
It does not establish a constant memory bound for an unlimited number of responses.

The inactive guard measurement uses five samples of one million calls each.
It reports the shortest thread CPU duration for each selector.
The empty control method measured 5.12 ns per call, and the production guard measured 2.06 ns per call.
These separate selectors are not equivalent machine-code baselines.
Their difference does not establish a speed improvement or an exact overhead.
The broad regression limit is 150 ns per production guard call on this host.

The runner also compiles a temporary mutation that disables the command guard.
That mutation fails the first paused return-shape assertion.
No production source changes are necessary for this negative control.

## Commands and results

Commands from the repository root:

```sh
python3 Tests/BackupReview/round3/luu/run.py
git diff --check -- Tests/BackupReview/round3/luu
```

Both commands exited with status 0.
The runner bounds compilation to 45 seconds and each child process to 30 seconds.
It deletes its temporary executables and data before completion.
The default runner asserts the current behavior.

```text
RETRY_COST panels=256 canceled_quits=63 original_reopen_attempts=257 checkpoint_repeats=0 restore_archive_writes=1 replacement_attempts=1 fd_growth_during_failures=0 resumed_fd_growth=1 rss_growth_bytes=2686976 return_shape_checks=1792
INACTIVE_GUARD iterations_per_sample=1000000 samples=5 control_ns=5.12 guard_ns=2.06 best_thread_cpu_seconds=0.002059
PASS: 32870 assertions; current extracted production methods, fixture UI/model/archive, real exclusive journal opens
PASS: removing the recovery command guard fails the first paused return-shape assertion
```

## Limits

No shipping Intel application opened because the known host stall occurs before application startup.
The fixture supplies dialog responses synchronously and cancels Quit before termination callbacks start.
It does not establish AppKit modal behavior, event scheduling, or complete application termination.
The round 2 evidence covers exceptions after termination starts. This scenario adds repeated cancellation and resource counts.

The probe does not simulate persistent dialog exceptions or measure filesystem latency on slow volumes.
It does not measure the full archive encoder, encryption, large libraries, or automatic backup workers.
It does not repeat the earlier history-scan benchmark.
All archive data consists of small fixture strings.
This review made no production edits or commits.
