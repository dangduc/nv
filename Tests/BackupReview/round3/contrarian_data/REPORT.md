# Round 3 — contrarian data-preservation review

No new actionable finding emerged from this bounded review. Severity: none.

This review covers [PR #8](https://github.com/fastducduc/nv/pull/8) at
`8ebbcb511415958f700ca54e4216e6447464d284`.
The PR base is `119c45302123c14d02dd0c9b620709bf68e6f086`.
This lens challenges the assumption that a restored library preserves data and identity through later use.
It does not represent an external reviewer.

The earlier data reviews covered archive formats, password history, failed checkpoints, pending conversions, conflicts, and deletion history.
This review adds restore, metadata edit, checkpoint, reopen, folder move, folder copy, publication, and deletion in related library namespaces.

## Executable evidence

From the repository root, run:

```sh
python3 Tests/BackupReview/round3/contrarian_data/run.py
```

Result: **196 checks passed**, exit status 0.
The unencrypted case and the encrypted case passed.
The host used macOS 26.5.2 (25F84) and Xcode 26.6 (17F113).
The runner stores its output in `build/BackupReview/round3/contrarian_data/results.log`.
It removes its disposable source folders and backup folders after each run.

The executable compiles the production `NoteObject`, `NotationPrefs`, `FrozenNotation`, `NVBackupArchive`, `NVBackupController`, and `NVBackupStore` implementations.
It also compiles unchanged `flushAllNoteChanges` and `backupSnapshotWithError:` methods from `NotationController`.
The probe establishes these results:

- A production store publication retains the exact archive bytes from the checkpoint.
  Offline restore assigns a new library UUID.
  The first controller attachment keeps that UUID and selects independent backup settings and a separate destination.
  Relevant code: `Sources/Preferences/NotationPrefs.m:298` and `Sources/Storage/NVBackupController.m:138`.
- A syntax change on an attached restored note changes only its current library preferences.
  The next checkpoint advances generation 1 to generation 2 and archives the new syntax.
  The capture metadata agrees with the archived library UUID and generation.
  Relevant code: `Sources/Model/NoteObject.m:125` and `Sources/Storage/NotationController.m:644`.
- Restore, checkpoint, and reopen preserve the note UUID, title, tags, authored dates, source encoding, and original source bytes.
  The unchanged export preserves a UTF-16 BE source with its BOM, CRLF, and Unicode characters.
  A clean capture and a clean reopen reuse the completed archive without another checkpoint write.
  Relevant code: `Sources/Model/NoteObject.m:1260` and `Sources/Storage/NotationController.m:704`.
- A folder move on the same volume keeps the restored library UUID, settings, and backup destination.
  A folder copy receives a third library UUID while the source folder remains present.
  Its first checkpoint stores that UUID at generation 1 and preserves the note UUID and syntax.
  Relevant code: `Sources/Storage/NVBackupController.m:128` and `Sources/Preferences/NotationPrefs.m:285`.
- A retention setting change in the restored library leaves the original settings unchanged.
  Plaintext deletion in the restored destination leaves both related libraries' archives unchanged.
  It also retains the restored encrypted archive in the encrypted case.
  Relevant code: `Sources/Storage/NVBackupController.m:88` and `Sources/Storage/NVBackupStore.m:663`.

The optional mutation checks whether the probe detects missing restore identity renewal:

```sh
python3 Tests/BackupReview/round3/contrarian_data/run.py --identity-mutation
```

Result: **expected failure**, exit status 1.
The mutation removes the offline UUID renewal from a temporary `NotationPrefs.m` copy.
The probe stops at `FAIL: offline restore assigns independent library identity`.
The runner stores that output in `build/BackupReview/round3/contrarian_data/mutation.log`.
The default command always uses current production sources and expects correct behavior.

## Limits

This native arm64 probe uses the existing UI scaffolding and CommonCrypto AES provider.
It uses production compression and portable PBKDF2 code.
It does not run the shipping Intel OpenSSL archive.
The compiler reports three existing warnings about `foregrndColor` declarations and a `BufferUtils.c` pointer cast.

Library initialization is a fixture that decodes the archive, attaches notes and preferences, and adopts the prepared password state.
It does not run the complete restored `NotationController` initializer.
Primary note synchronization and journal synchronization return success.
The fixture uses ordinary atomic file writes for checkpoints and omits disk-metadata cleanup.

The controller identity and settings methods run with in-memory defaults and a disposable application-support directory.
The controller timer and worker are absent.
The probe calls the production store synchronously, so it does not establish worker scheduling or callback behavior.
It exercises default backup destinations, same-volume folder moves, and copies whose source folders still exist.
It does not establish bookmark behavior, cross-volume moves, crash durability, or concurrent external edits.

No Intel application process ran during this review.
The known startup stall still prevents full desktop recovery validation on this host.
The new restore command guards and external-editor preflight receive separate round 3 lifecycle reviews.
This review adds no production edits or commits.
