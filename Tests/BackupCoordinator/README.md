# Backup coordinator checks

```sh
python3 Tests/BackupCoordinator/run.py
```

The test compiles the production `NVBackupController` with an in-memory library and defaults.
A fake clock and manual worker and completion queues control each transition without sleeping.
The test creates placeholder snapshot folders under a temporary directory.
It does not open windows or a notes library.

The checks cover interval scheduling, unchanged content, edits during a job, clock changes, wake, failures, retries, library replacement, termination, and restart.
They also cover disablement, manual backups, and backup identity after moving or copying a library.
An unchanged generation must verify the previous archive on the worker before it skips publication.
The checks cover intact, corrupt, missing, and different archive bytes, plus foreign paths and obsolete verification callbacks.
The capture date must remain unchanged after successful verification.
Selected destinations must include their existing root and device/inode identity in worker metadata.
Corrupt persisted settings must use valid defaults or report an unavailable selected destination.
The checks cover malformed types, numeric bounds, non-finite dates and numbers, broken bookmarks, and malformed library-location records.
They verify that an old job keeps its original data and destination and cannot advance a new library's status.
The archive and storage tests cover actual archive recovery and filesystem publication.
