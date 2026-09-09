# Periodic automatic backups

Accepted design for the automatic backup implementation. See `automatic-backups.md` for the implemented controls and limits.

## Behavior before this change

Before this change, nvALT had automatic saves and crash recovery. It did not have periodic historical backups, retention settings, or a backup restore interface.
The audit covers commit `119c45302123c14d02dd0c9b620709bf68e6f086`.

| Existing mechanism | Behavior | Source |
| --- | --- | --- |
| Automatic save | Requests a write after 2.7 seconds without an edit, or through a 15-second timer during continued edits. Run-loop activity can delay these requests. | [NotationController.m](https://github.com/fastducduc/nv/blob/119c45302123c14d02dd0c9b620709bf68e6f086/Sources/Storage/NotationController.m#L1011) |
| Recovery journal | Appends changes and recovers them after an interrupted session. A successful close deletes the journal. | [Journal recovery](https://github.com/fastducduc/nv/blob/119c45302123c14d02dd0c9b620709bf68e6f086/Sources/Storage/NotationController.m#L355), [journal closure](https://github.com/fastducduc/nv/blob/119c45302123c14d02dd0c9b620709bf68e6f086/Sources/Storage/NotationController.m#L513) |
| Database save | Writes the current notes and library settings to `Notes & Settings`. Atomic replacement deletes the previous contents. | [Database flush](https://github.com/fastducduc/nv/blob/119c45302123c14d02dd0c9b620709bf68e6f086/Sources/Storage/NotationController.m#L542), [atomic replacement](https://github.com/fastducduc/nv/blob/119c45302123c14d02dd0c9b620709bf68e6f086/Sources/Storage/NotationFileManager.m#L546) |

These mechanisms preserve current work. They do not provide dated copies for recovery after an accidental edit or deletion.

## Proposed behavior

| Setting | Proposed default |
| --- | --- |
| Automatic backups | Enabled after the library opens successfully. The user can disable them in Preferences. |
| Interval | Every 15 minutes, with a new snapshot only after a committed library change. |
| Destination | `~/Library/Application Support/nvALT/Backups/<library UUID>/`, with a selectable alternative folder. |
| Retention | The newest 96 snapshots, the latest snapshot per day for 30 days, and the latest per week for 12 weeks. |
| Storage target | 2 GiB per library. Delete the oldest eligible snapshots first, but preserve at least three complete snapshots. |
| Manual actions | Back Up Now, Show Backups in Finder, and Restore Backup. |
| Status | Last successful backup, next due time, destination, storage use, and the latest error. |

Retention uses the union of these groups, without duplicate copies. Daily and weekly groups use UTC calendar boundaries.
The storage target takes priority over older daily and weekly history. If three snapshots exceed the target, nvALT retains them and shows the excess.
Backup settings belong to the local installation and library identity. Backup status changes do not trigger another backup.

The first snapshot follows successful startup recovery and directory reconciliation.
After launch or wake, one overdue backup captures the current committed state. nvALT does not create copies for missed intervals.
The schedule continues with all browser windows closed, while the application remains open.
The initial release does not run a background agent while nvALT is closed.

The local destination protects history against accidental changes. A copy on the same disk does not protect against disk failure.
The destination must sit outside the active notes folder. Folder checks resolve aliases and symbolic links to prevent recursive inclusion.
If a selected volume is unavailable, nvALT retains the last successful backup and retries with a bounded delay.
It does not silently switch destinations or show repeated modal alerts.

## Snapshot contents and capture

Each snapshot contains one complete library archive and a small, versioned manifest.
The manifest records the library identity, snapshot identity, capture time, app version, format version, archive size, and SHA-256 checksum.
It contains no note titles, source text, passwords, or keys.

The archive preserves note UUIDs, titles, tags, dates, source text, original source bytes, encoding, byte-order marks, and pending encoding conversions.
It also preserves library settings, including local syntax metadata.
Both database storage and separate text-file storage use this archive representation.
The archive contains the committed note model, including pending source-file conversions that a directory copy can miss.

External file changes enter a snapshot after normal directory reconciliation imports them into the model.
Active input-method composition remains active. A snapshot uses committed text and captures the resulting edit after composition finishes.
The status describes this boundary for Back Up Now, including any pending edits that the snapshot excludes.
Snapshots do not include Undo history, browser layouts, preview caches, or arbitrary linked files outside the note model.
Managed native payloads will require an explicit extension to the backup format before their storage feature ships.

`NVApplicationController` owns one proposed `NVBackupController` for the shared library.
Browser windows expose actions and status but do not own timers or perform library I/O.
The controller stops scheduling during library replacement and termination.
Jobs carry their original library identity and destination. Cancellation prevents an old job from updating the new library's status or retention.

`NotationController` supplies an immutable archive from its serialized save boundary on the main thread.
The first implementation reuses the exact archive bytes from a successful database checkpoint.
It does not copy a changing notes directory or hand mutable notes and preferences to a worker.
One serial worker writes, checks, publishes, and prunes backups.

Two existing details require care:

- `FrozenNotation` encryption changes the live preference salt through `encryptDataInNewSession:`. Independent serialization on a worker can disturb a concurrent save.
- `flushAllNoteChanges` returns the archive-save result. It logs some journal errors without returning failure, so its Boolean result cannot establish backup success.

The capture API must return the exact archive bytes, capture generation, and explicit error state.
Primary source-file errors remain visible separately from backup status. A complete archive can contain newer source text than an unchanged external file.
Backup success requires a complete destination write and a checksum check against the captured bytes.
Archive recovery tests must compare content and metadata, beyond the existing save check of note counts and text lengths.

A persistent generation covers note creation, edits, deletion, Undo, imported external changes, syntax changes, and relevant library settings.
The same archive transaction stores the content and its capture generation. Separate writes can misidentify saved changes after a crash.
Only a successful publication advances the recorded backup generation.
An edit during a backup leaves a newer generation pending. A restart cannot mistake an unfinished job for a successful backup.
Moving a library retains its backup identity. Restoring or independently copying a library must establish a separate destination identity to prevent shared pruning.

## Publication, encryption, and retention

A job creates a private staging directory inside the destination.
It writes the archive and manifest, checks their contents, and completes the required file synchronization.
It then publishes the complete directory with a same-volume atomic rename and completes destination-directory synchronization.
Failures preserve earlier complete snapshots. Startup ignores incomplete staging directories and cleans only staging entries owned by nvALT.
Retention runs only after successful publication and touches only complete snapshots owned by that library.
The implementation must exercise filesystem failure paths before it claims recovery after a crash or power loss.

Encrypted libraries retain the existing encrypted note payload. The worker receives the serialized archive, not plaintext exports or secret keys.
The existing archive leaves some library settings, including syntax metadata, outside its encrypted note payload.
The interface must not claim that the entire backup is encrypted.
Snapshot directories and files use private permissions. Error logs exclude note content and secrets.

A password change applies to future snapshots. Older encrypted snapshots can require their original password.
Enabling encryption does not encrypt older plaintext snapshots. The settings flow must explain this and offer a separate action to delete that older history.
Automatic retention remains separate from that explicit deletion action.

## Restore

Restore Backup first checks the manifest, checksum, supported format, archive structure, and any required password.
An incorrect password, damaged archive, or canceled restore leaves the active library and existing backups unchanged.
The interface then shows the capture date and note count and requests a new, empty destination folder.

The initial release restores into a new library. Replacing the active library in place is outside this release.
Restore preserves note UUIDs and syntax associations but assigns a new library identity.
It discards active filesystem references, old directory associations, and journal identity before it attaches the restored model.
It opens the recovered library in database storage. The user can later select separate text-file storage through the existing conversion flow.

This storage override is required. A saved text-file library expects its individual files during startup reconciliation.
Opening only its archive in an empty folder can otherwise treat every missing file as an external deletion.
Restore must decode the archive through a controlled path before normal library initialization starts filesystem monitoring.
It must not reuse or delete the active library's recovery journal.

The current journal uses one application-wide cache filename. Offline decoding must not initialize a second `NotationController` or its journal.
After recovery checks pass, the coordinator commits pending edits and safely flushes and closes the old library before it opens the restored library.
If the old library cannot close safely, the switch stops. If the new library cannot open, the coordinator reopens the original library.

## Implementation sequence

| Step | Work | Completion criterion |
| --- | --- | --- |
| 1. Capture and restore | Add the archive capture result, library identity, format manifest, and controlled restore path. | Both storage modes restore exact source and metadata into a new library. |
| 2. Backup storage | Add staged publication, checksums, private permissions, retention, and explicit error results. | Interrupted or failed writes leave earlier snapshots recoverable. |
| 3. Schedule and lifecycle | Add the shared coordinator, persistent generations, interval, wake handling, and cancellation. | Multiple windows produce one schedule. Edits during backup remain pending. |
| 4. Preferences and actions | Add enablement, destination, interval, retention settings, status, and manual backup and restore actions. | The user can find a backup and recover a deleted note without modifying the original library. |
| 5. Release checks | Add new files to the Xcode target and document ownership in `architecture.md`. Run the Development build and both desktop suites. | The checks pass with disposable notes, and performance results document the capture cost. |

## Required evidence

- A fake clock covers interval expiry, unchanged libraries, continuous edits, sleep, wake, clock changes, and restart after failure.
- Round-trip fixtures cover database and text-file storage, encryption, old passwords, Unicode, tags, syntax-only changes, deletions, and pending encoding conversions.
- Composition and multiple-window checks establish that backups do not end composition, duplicate schedules, or lose edits after capture.
- Failure injection covers full disks, permission errors, unavailable volumes, partial writes, synchronization failures, interrupted publication, and failed retention.
- Restore checks include checksum corruption, unsupported formats, canceled passwords, empty libraries, and the missing-text-file deletion trap.
- Destination checks cover moved libraries, copied libraries, symbolic links, and unrelated files that retention must preserve.
- Measurements cover main-thread capture time, peak memory, and backup duration for 1,000 and 10,000 representative notes, including large source files.

Scheduling and retention checks can run without a desktop session.
Full recovery and lifecycle checks use copied applications and disposable libraries.
The release requires a successful restore from a backup after the original disposable library and journal are unavailable.
