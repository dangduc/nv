# Retention enforcement and retry

Addresses PR #8 comments `5593782355` and `5593766509`.

The controller tracks maintenance separately from snapshot publication.
It applies retention after a policy change, after a previous maintenance failure, and after library attachment.
It also applies retention on the first due check of each new UTC day so daily and weekly history can expire in a quiet library.
Other unchanged checks verify the current archive without scanning all history again.

An unchanged archive no longer requires a duplicate publication to apply retention.
The controller preserves the prior backup date and snapshot path during maintenance.
Maintenance failures retry after five minutes. Their error remains visible while retry work runs and clears after cleanup succeeds.
Library switching retains the existing context guard: an old completion cannot clear the new library's pending maintenance or alter its status.

The new store overload, `pruneSnapshotsInDirectory:metadata:retention:error:`, validates the expected library owner.
For a custom folder it also validates the captured root device and inode before opening its library child.
Maintenance does not recreate an unavailable root or missing library directory.
The optional `protectedSnapshotIdentifier` preserves the verified current snapshot across clock changes and equal-date publications.
The original pruning API remains available to existing callers.

The shared directory-opening helper now accepts a creation flag. Publication passes `YES`; maintenance passes `NO`.
Archive checksum verification remains unchanged.
The duplicate full-history status scan measured in round 1 remains a possible later optimization.
This fix does not remove that scan or weaken integrity checks.

## Validation

Commands run from the repository root:

```sh
python3 Tests/BackupCoordinator/run.py
python3 Tests/BackupStore/run.py
python3 Tests/BackupReview/round1/luu/run.py
python3 Tests/BackupReview/round1/luu/run.py --baseline
python3 Tests/BackupReview/round1/ousterhout/run.py
python3 Tests/BackupReview/round1/ousterhout/run.py --baseline
xcrun clang --analyze -fblocks -fno-objc-arc -Wall -Wextra -Werror -mmacosx-version-min=10.13 -I Sources/Storage Sources/Storage/NVBackupStore.m -o build/backup-store-review-analysis.plist
```

All commands passed. The store suite now passes 372 assertions and compiles with warnings treated as errors.
Clang static analysis reported no store findings.

The coordinator adds checks for policy changes, unchanged policy submissions, transient maintenance failure, bounded retry, and error persistence during retry.
It also checks daily maintenance, custom-root metadata, preserved backup identity, and a library switch before maintenance completion.
The store adds checks for unavailable or replaced roots, missing child directories, foreign ownership, failed pruning, and protected current snapshots.

The integrated controller/store reproduction reports `3 / 3 / 3` retained packages after the fix.
Its baseline mode still reports `5 / 5 / 4`, with the last error cleared prematurely.
Both modes use disposable real packages with fixture library objects, dates, defaults, and queues.
The baseline mode obtains production files from the recorded initial commit with `git show`.

These native checks do not validate window switching, primary checkpoint capture, journal lifecycle, or shipping Intel OpenSSL.
No Intel application was launched during this fix.
