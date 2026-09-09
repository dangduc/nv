# Round 2: crash recovery and consistency review

This review uses a Kyle Kingsbury-inspired failure and consistency lens. Kyle Kingsbury did not perform this review.

Baseline: `a89f8351646f824f51ed6ea80b94f724f37d0303`.
Feature baseline: `30c3cf816c80e4ff957223d55f22b36074880ef1`.
PR base: `119c45302123c14d02dd0c9b620709bf68e6f086`.

Environment: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), native arm64 probe.
The review made no production edits or commits.

## P1: Prevent later edits after journal rollback fails

Primary location: `Sources/Application/NVApplicationController.m:258`.

After replacement initialization fails, the coordinator calls the original library's journal resume method.
If exclusive journal creation also fails, the coordinator still clears `restoring` and returns to the original library.
Its browsers remain attached, but `backupRestorePrepared` remains true and `walWriter` remains nil.

Later database edits enter the normal autosave queue at `Sources/Storage/NotationController.m:1215`.
The timer drains that queue at line 895 without a journal write or a database checkpoint.
The same method sets `lastWriteError` to `noErr` at line 879.
Backup capture cannot provide its usual checkpoint because the prepared-state guard returns first at line 673.

This is a crash-loss risk, not inevitable loss on clean shutdown.
The dirty flag remains true. An explicit `flushAllNoteChanges` still saves the later edits.
Clean termination calls that method at `Sources/Browser/AppController.m:1828`.
Until such a checkpoint occurs, process failure loses the later edits because neither primary persistence path contains them.

The unsafe state persists after journal contention ends.
A normal restore retry stops at the prepared-state guard on `Sources/Storage/NotationController.m:716`.
It never reaches the only application call to `resumeAfterBackupRestoreFailureWithError:`.
A direct call to that internal method succeeds after contention ends, but no user action or scheduled retry calls it from this state.

The round-one guard correctly preserves the competing journal. This finding concerns the caller's resulting state after that refusal.
The coordinator must prevent a return to editable operation until exclusive journal resume succeeds.
A bounded recovery dialog with Retry and Quit can keep this transition explicit.
The retry must preserve the exclusive-create rule and leave the competing journal untouched.

## Executable evidence

Run:

```sh
python3 Tests/BackupReview/round2/kingsbury/run.py
```

The control process passed 29 assertions.
It exercised a failed replacement, failed rollback, later edits, ended contention, an ordinary restore retry, direct checkpoint recovery, and internal journal recovery.
The second process passed 22 assertions before `_exit(73)` skipped all save and deallocation paths.
The parent then checked its checkpoint bytes and absent journal.

```text
FAILED_ROLLBACK: original_selected=1 restoring=0 prepared=1 writer=0 queue=0 journal_writes=0 checkpoint_writes_after_edit=0
CONTENTION_ENDED: restore_retry_error=4 replacement_attempts=1 prepared=1 writer=0 durable_text=before_restore
CONTROL: explicit_checkpoint_saved=1 internal_resume_succeeded=1 later_autosave_journal_writes=1
PASS: 29 assertions; extracted production methods, fixture model/archive/UI, real journal and checkpoint filesystem writes
FAILED_ROLLBACK: original_selected=1 restoring=0 prepared=1 writer=0 queue=0 journal_writes=0 checkpoint_writes_after_edit=0
CONTENTION_ENDED: restore_retry_error=4 replacement_attempts=1 prepared=1 writer=0 durable_text=before_restore
ABRUPT_EXIT: 22 assertions before exit without save or deallocation
PASS: separate process exited without cleanup; durable checkpoint predates both later edits; no journal remains
```

The runner extracts the current application restore method and eight storage methods or functions.
These include journal initialization, preparation, resume, capture, full checkpoint, autosave, scheduling, and checkpoint synchronization.
The probe calls the exact autosave timer selector after it schedules each edit. It does not wait for the timer deadline.
Its positive control shows that the same autosave path writes a journal record after internal recovery.

## Scope and limits

The note model, archive encoder, preference object, replacement initializer, restore writer, monitoring, and UI are fixtures.
The journal fixture uses real exclusive creation, writes, `fsync`, and unlink operations.
The full-checkpoint method uses a fixture encoder and actual temporary-file writes.
The extracted checkpoint synchronization function reads those bytes and synchronizes their file and directory.
The fixture does not implement journal encryption, compression, or the shipping record decoder.

The abrupt exit demonstrates missing persisted bytes in this fixture. It does not run shipping startup recovery or the full browser UI.
The known Intel app startup stall prevents full-application validation. This review did not launch that app.
The finding targets database storage. Separate text-file storage can still write individual source files and requires a separate durability assessment.

The review inspected the round-one rollback correction and the current restore retry path.
It found no additional independent issue within this bounded scope.
Other round-two reports cover preferences closure, backup folder ownership, scheduling, and numeric validation.
