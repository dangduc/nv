# Round 3: checkpoint and journal handoff

This review uses a Kyle Kingsbury-inspired consistency and recovery lens.
Kyle Kingsbury did not perform this review.

PR: https://github.com/fastducduc/nv/pull/8

Production baseline: `8ebbcb511415958f700ca54e4216e6447464d284`.
Host: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), native arm64.

**No new actionable finding emerged from this bounded review.**

The probe checks the boundary between active checkpoint synchronization and journal removal.
Earlier probes used a fixture journal for this boundary.
This probe runs the production journal synchronization and removal methods with real file descriptors.

The preparation method preserves the original journal after every injected failure.
The same descriptor accepts subsequent fixture bytes.
A successful retry captures those bytes before journal removal.
Relevant locations are `Sources/Storage/NotationController.m:748` and `Sources/Storage/WALController.m:96`.

The successful operation order is checkpoint file synchronization, checkpoint directory synchronization, journal synchronization, then journal removal.
The timer and monitoring remain active after refusal.
Successful preparation invalidates the timer, stops monitoring once, and sets the prepared state.
Relevant locations are `Sources/Storage/NotationController.m:68`, `Sources/Storage/NotationController.m:752`, and `Sources/Storage/NotationController.m:756`.

## Executable evidence

Run these commands from the repository root:

```sh
python3 Tests/BackupReview/round3/kingsbury/run.py
python3 Tests/BackupReview/round3/kingsbury/run.py --negative-controls
```

Both commands returned exit status 0.
The default run passed 297 native assertions across 13 isolated processes.
The Python parent also checked the checkpoint bytes after the abrupt process exit.

| Scenario | Native assertions | Observed result |
| --- | ---: | --- |
| Complete checkpoint | 14 | Preparation succeeds in the required order |
| Positive short reads of at most 997 bytes | 14 | All 131,103 bytes pass the comparison loop |
| One changed byte at offset 70,000 | 25 | Refusal preserves the journal, then retry succeeds |
| Checkpoint truncated by one byte | 25 | Refusal preserves the journal, then retry succeeds |
| Missing checkpoint | 24 | Refusal preserves the journal, then retry succeeds |
| Checkpoint symlink to identical bytes | 25 | Refusal preserves the journal, then retry succeeds |
| Checkpoint directory symlink | 25 | Refusal preserves the journal, then retry succeeds |
| Checkpoint read returns `EIO` | 24 | Refusal preserves the journal, then retry succeeds |
| Checkpoint file synchronization returns `EIO` | 25 | Refusal preserves the journal, then retry succeeds |
| Checkpoint directory synchronization returns `EIO` | 26 | Refusal preserves the journal, then retry succeeds |
| Journal synchronization returns `EIO` | 28 | No unlink attempt occurs before refusal |
| Journal unlink returns `EACCES` | 28 | Refusal preserves the writable descriptor, then retry succeeds |
| `_exit(73)` after successful preparation | 14 | The parent reads every checkpoint byte and finds no journal |

Each failure scenario appends new fixture content through the retained journal descriptor after the failure ends.
The subsequent preparation captures the combined content and removes the journal.
This sequence checks preservation and retry ordering without another journal object.

The optional negative controls change only temporary compilation inputs.
Ignoring checkpoint comparison failure causes the expected refusal assertion to fail.
Closing the descriptor before a failed unlink causes the descriptor-preservation assertion to fail.

## Scope and limits

The runner extracts four production bodies without edits:

- `NVSynchronizeBackupCheckpoint`
- `prepareForBackupRestoreWithError:`
- `synchronize` from `WALStorageController`
- `destroyLogFilePreservingWriterOnFailure`

The note model, archive capture, monitoring callback, and journal creation are fixtures.
The ODB fixture reports no active sessions.
The journal buffer callback reports an empty buffer.
The fixture appends raw bytes through the real descriptor instead of the application autosave or journal encoder.
The timer is a real scheduled `NSTimer`, but its deadline does not occur during the probe.

Checkpoint alterations affect real disposable files after fixture capture and before production preparation continues.
The wrappers inject explicit read, synchronization, and unlink errors.
Other POSIX operations run normally, including descriptor identity checks, writes, synchronization, close, and unlink.
Compilation uses `-Wall -Wextra -Werror` with explicit exclusions for unused parameters and legacy warnings.

The abrupt process exit skips save and deallocation paths.
It establishes process-exit preservation at one boundary, not power-loss durability or shipping startup recovery.
This probe does not run compression, encryption, archive decoding, the replacement initializer, or browser attachment.
It does not test concurrent filesystem mutation or actual permission changes.

The Intel application remains stalled before `main` on this host.
This review launched no Intel application and used no personal notes.
The review made no production edits or commits.
