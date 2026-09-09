# Round 1: measurement and resource costs

Dan Luu-inspired review lens. This review is not authored by Dan Luu.

PR: #8. Baseline: `30c3cf816c80e4ff957223d55f22b36074880ef1`.
Changes reviewed against `119c45302123c14d02dd0c9b620709bf68e6f086`.
Host: macOS 26.5.2, Xcode 26.6, native arm64 probes.

## Finding

**[P2] Apply retention after policy changes and retry failed pruning for unchanged notes.**

Location: `Sources/Storage/NVBackupController.m:291`, with policy rescheduling at lines 171–174.

An unchanged checkpoint takes the verification shortcut and returns without retention.
Changing retention therefore does not reduce existing backup storage until a new snapshot is published.
A transient pruning failure has the same problem: the next verification clears its error without retrying pruning.
This leaves excess snapshots while the status no longer reports the failure.

The executable probe uses the production coordinator and filesystem store together.
It creates five real packages, lowers retention to three, and runs two automatic checks.
Both checks leave five packages. A manual publication immediately applies the same policy and leaves three.
It then injects one store pruning failure. The next automatic check leaves four packages and clears the error.

Fix the unchanged branch to apply pending retention and keep an unresolved retention error visible.
Do not require an unrelated note edit or another manual backup to enforce the selected policy.
This independently confirms the retention issue also found by the Ousterhout-inspired review.

## Cost measurement

The current success path scans complete archive data twice: once during pruning and again for the storage status total.
The second scan occurs at `NVBackupController.m:286`; the first starts at `NVBackupStore.m:538`.

With 96 existing 1 MiB packages, publishing one 1 MiB package read 98 MiB of archive data.
The status listing then read another 97 MiB. Total archive reads were 195 MiB.
The measured local, warm-cache times were 51.38 ms for publication and 47.87 ms for status listing.
Peak process RSS was 13.56 MiB, including the bounded fixture setup.

This is a cost observation, not a separate blocking finding. Per-package autorelease pools keep listing memory bounded.
The work runs on the serial backup worker. These measurements do not show an editor pause.
Returning the verified retained size from the publication operation could remove the second archive scan.
Do not drop integrity checks solely to improve this metric.

## Executable evidence

Command:

```sh
python3 Tests/BackupReview/round1/luu/run.py
```

Output:

```text
RETENTION_GAP stricter_policy_count=5 next_tick_count=5 failed_prune_next_tick_count=4 prune_error_cleared=yes
PASS: bugs reproduced with production controller + filesystem store; library, defaults and queues are fixtures
STORE_COST retained_before=96 archive_mib=1 publish_archive_read_mib=98 status_archive_read_mib=97 total_archive_read_mib=195 publish_ms=51.38 status_ms=47.87 peak_rss_mib=13.56
PASS: measured actual production filesystem operations; no GUI or archive decoder
```

The reproduction asserts the baseline defect, so its passing exit is not a corrected-behavior regression check.
`run.py` reuses fixture services from the coordinator harness and compiles unchanged production controller and store files.
`store-cost.m` wraps only the store's POSIX `read` calls to count returned archive bytes.
It verifies all 96 fixture packages with the production checksum path before measurement.
The package contents are arbitrary bytes, not decoded note archives.
All files are disposable and removed by the runner.

## Limits

The probes do not run AppKit windows, journal switching, primary checkpoint capture, or shipping Intel OpenSSL.
Timing describes one local run and does not predict removable-drive or network-drive latency.
The coordinator uses fake library objects, defaults, dates, and controlled queues.
No Intel application was launched because this host stalls before application startup.
The existing native archive measurement already documents a main-thread capture cost for larger libraries.
This review did not repeat that larger memory fixture or claim it measures the full primary write path.
