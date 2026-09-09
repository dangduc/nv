# Round 2: maintenance frequency, retries, and memory

Dan Luu-inspired review lens. Dan Luu did not author this review.

PR: #8. Reviewed revision: `a89f8351646f824f51ed6ea80b94f724f37d0303`.
Initial PR revision: `30c3cf816c80e4ff957223d55f22b36074880ef1`.
PR base: `119c45302123c14d02dd0c9b620709bf68e6f086`.
Host: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), native arm64 probes.

## Finding

**[P3] Preserve the five-minute maintenance retry for shorter backup intervals.**

Location: `Sources/Storage/NVBackupController.m:231`, with the new maintenance deadline at `Sources/Storage/NVBackupController.m:320`.

After maintenance fails, the controller sets its next attempt to 300 seconds later.
The timer then mistakes this deadline for a backward clock change if the configured interval is shorter than 300 seconds.
It replaces the retry deadline with the configured interval.

The production controller accepts a 60-second interval at `Sources/Storage/NVBackupController.m:160`.
With that interval and a timer tick 30 seconds after failure, the next cleanup attempt occurs after 90 seconds.
The clock never moves backward in the probe.
The default 900-second interval preserves the full 300-second retry.

The preferences menu starts at 300 seconds, so this defect requires settings that select the shorter supported interval.
This limits its ordinary UI exposure and supports P3 severity.
The effect is extra worker and storage activity during repeated failures, without loss of a previous snapshot.

The clock correction predates the round 1 fix.
The new retry for unchanged maintenance inherits that correction and exposes it to repeated history scans.
The correction must distinguish a real backward clock change from a deliberate failure deadline.

## New evidence

The frequency probe combines the unchanged production controller and filesystem store.
It substitutes the library, defaults, clock, and queues.
The archive data contains arbitrary fixture bytes, so this probe does not measure archive capture or decoding.

The probe checks 32 complete packages of 1 MiB each through the production checksum path.
It counts returned archive bytes from the store's POSIX `read` calls.
It does not count small plist reads or filesystem metadata operations.

| Operation | Archive bytes read | Result |
| --- | ---: | --- |
| Changed retention settings | 65 MiB | One current archive plus two complete history scans |
| Four ordinary unchanged checks | 4 MiB total | One current archive per check |
| Unchanged retention submission | 1 MiB | No history scan |
| Interval change | 1 MiB | No history scan |
| First due check on a new UTC day | 65 MiB | One maintenance operation |
| Next check on the same UTC day | 1 MiB | No history scan |
| Injected failure before pruning | 33 MiB | Current archive plus history for status |
| Successful cleanup retry | 65 MiB | Cleanup and status scans complete |

The failure remains visible while retry work waits in the queue.
It clears after cleanup succeeds.
All unchanged operations preserve the successful snapshot path and date, without duplicate packages.
These assertions extend the round 1 checks with actual filesystem read counts.

The memory probe uses separate processes with 8 and 48 packages of 2 MiB each.
The retained history increases from 16 MiB to 96 MiB.
Peak process RSS increases from 14.89 MiB to 15.08 MiB in this run.
The probe asserts that the increase stays within 16 MiB and that the larger process stays below 48 MiB.

Every archive passes the production checksum path during the measured listing.
The returned entries contain no archive payloads.
These measurements support the per-package autorelease pool at `Sources/Storage/NVBackupStore.m:330` for this fixture range.
They do not establish a constant memory bound for every package count or archive size.
The store still retains names and snapshot metadata in proportion to package count.

The duplicate history scan remains a cost observation, with no additional blocker.
This review does not repeat the prior 96-package publication benchmark or the large archive capture fixture.

## Compiler-flags check

The project enables fast math at `Notation.xcodeproj/project.pbxproj:2439` and `Notation.xcodeproj/project.pbxproj:2535`.
The probe compiles the production controller and store with `-O1`, both with and without `-ffast-math`.
Each binary rejects 30 invalid numeric settings.
The cases cover NaN, positive infinity, negative infinity, strings, null, and fractional numbers across five settings.
Both binaries accept the valid lower bounds.

The fast-math build emits the existing warning about `NAN` at `Sources/Storage/NVBackupController.m:165`.
This native probe shows no behavioral defect from that warning for these cases.
It does not establish Intel code-generation equivalence or cover saved-defaults decoding.

## Commands and results

Commands from the repository root:

```sh
python3 Tests/BackupReview/round2/luu/run.py --settings-only
python3 Tests/BackupReview/round2/luu/run.py
git diff --check -- Tests/BackupReview/round2/luu
```

All commands exited with status 0.
The default command compiles each native executable, creates disposable files, runs each probe, and deletes those files.
The retry assertion reproduces the defect. Its passing exit does not mean that the retry behavior is correct.

Final default-run result lines:

```text
SETTINGS_NUMERIC cases=30 invalid_accepted=0
SETTINGS_BUILD mode=ordinary exit=0
SETTINGS_NUMERIC cases=30 invalid_accepted=0
SETTINGS_BUILD mode=fast-math exit=0
RETENTION_READS packages=32 archive_mib=1 policy_mib=65 ordinary_checks=4 ordinary_total_mib=4 daily_mib=65 failed_prune_mib=33
RETRY_BOUND interval_900_retry_seconds=300 interval_60_retry_seconds=90 expected_failure_retry_seconds=300
PASS: production controller/store schedule and read assertions; minimum-interval assertion reproduces the retry defect
LIST_MEMORY packages=8 archive_mib=2 retained_archive_mib=16 peak_rss_bytes=15613952 peak_rss_mib=14.89
LIST_MEMORY packages=48 archive_mib=2 retained_archive_mib=96 peak_rss_bytes=15810560 peak_rss_mib=15.08
PASS: 6x archive history increases peak RSS by at most 16 MiB; larger process stays below 48 MiB
```

## Scope limits

No shipping Intel application was opened because the known host failure occurs before application startup.
These native substitutes do not cover AppKit window behavior, primary checkpoint capture, journal switching, encryption, or restore.
The controlled queues run operations synchronously and do not measure concurrency timing or editor responsiveness.
The read counters measure bytes returned from system calls, not physical disk traffic or latency on removable and network volumes.
The memory result covers bounded filesystem-store fixtures. It does not measure the memory cost of a full library archive.
This review makes no production edits or commits.
