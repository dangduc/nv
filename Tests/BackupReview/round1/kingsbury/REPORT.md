# Round 1: Kyle Kingsbury-inspired review

This review applies a consistency and failure-recovery lens. Kyle Kingsbury did not perform this review.

Baseline: `30c3cf816c80e4ff957223d55f22b36074880ef1`, compared with `119c45302123c14d02dd0c9b620709bf68e6f086`.

## Finding: P1 — Keep failed-restore rollback exclusive

Location: `Sources/Storage/NotationController.m:770`.

`prepareForBackupRestoreWithError:` closes the active library's journal before the replacement opens its own journal. Both use the application-wide cache pathname.
If another app instance creates that journal during the gap, the replacement correctly refuses to open it.
The rollback then calls ordinary `initializeJournaling`, which permits recovery because `openingRestoredLibrary` is false.
It can pass another library's records to `processRecoveredNotes:`, delete that journal, and report successful rollback.
The competing writer retains an unlinked descriptor. Subsequent records written through that descriptor have no pathname for recovery.

The recovery branch is at lines 454–483. `NotationPrefs.m:574–581` also shows that unencrypted libraries use the same WAL key.
An incompatible or empty journal can still reach the branch that deletes it, even if no records decode.

Rollback from a prepared restore should use the same exclusive-creation rule as replacement initialization.
If the pathname is occupied, it should preserve that file and report that the original journal could not reopen.
The caller must keep that failure visible; it must not claim a completed rollback.

## Executable evidence

Run:

```sh
python3 Tests/BackupReview/round1/kingsbury/run.py
```

The runner extracts the production `initializeJournaling` and `resumeAfterBackupRestoreFailureWithError:` methods.
It compiles them natively with filesystem-backed WAL stubs, using only a temporary directory.
The fixture keeps a competing descriptor open while exercising replacement failure followed by rollback.

Observed output:

```text
BASELINE ISSUE: reported success, foreign-note processing calls=1, deleted journals=1, competing descriptor links=0
PASS: 10 assertions (baseline), extracted production methods; WAL crypto/decoder/UI are stubs
GUARDED: refused collision, recovery calls=0, deleted journals=0, competing descriptor links=1
PASS: 10 assertions (guarded), extracted production methods; WAL crypto/decoder/UI are stubs
```

The second run adds `backupRestorePrepared` to the existing recovery guard in memory.
That candidate preserves the competing file and refuses the collision. Uncontended rollback still succeeds.
The probe does not edit production code.

## Scope and limits

The probe verifies actual caller control flow, real exclusive file creation, unlinking, and descriptor link counts.
WAL encryption, note decoding, checkpoint storage, monitoring, and UI services are stubs.
It does not run the full application or prove shipping OpenSSL behavior.
The host's Intel app currently stalls before startup, so this review did not launch it.

The review also inspected destination identity and stale-completion guards. No additional supported issue was found there.
Retention on unchanged checkpoints is covered by another round-one reviewer and is not repeated here.
