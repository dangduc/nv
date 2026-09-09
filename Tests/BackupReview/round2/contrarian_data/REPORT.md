# Round 2 — contrarian data-preservation review

No new actionable finding emerged from this bounded review.

This review covers PR #8 at `a89f8351646f824f51ed6ea80b94f724f37d0303`.
The initial review baseline was `30c3cf816c80e4ff957223d55f22b36074880ef1`.
The PR base was `119c45302123c14d02dd0c9b620709bf68e6f086`.
The review challenges archive completeness and recovery after ordinary storage failures.
It does not represent an external reviewer.

## Evidence

From the repository root, run:

```sh
python3 Tests/BackupReview/round2/contrarian_data/run.py
```

Result: **258 checks passed**, exit status 0.
Both the encrypted case and the unencrypted case passed.
The host used macOS 26.5.2 (25F84) and Xcode 26.6 (17F113).
The runner stores its output in `build/BackupReview/round2/contrarian_data/results.log`.

The executable uses the production `NoteObject`, `NotationPrefs`, `FrozenNotation`, and `NVBackupArchive` implementations.
It also compiles two unchanged methods from `NotationController`: `flushAllNoteChanges` and `backupSnapshotWithError:`.
These methods run in a small fixture with explicit storage outcomes.

The fixture establishes these results:

- A completed capture contains the same bytes as its checkpoint.
  A clean capture reuses those bytes without another checkpoint attempt.
  Relevant code: `Sources/Storage/NotationController.m:664` and `Sources/Storage/NotationController.m:704`.
- Disk-full and permission failures restore the previous generation and capture date.
  The changed metadata remains dirty, and the previous disk bytes and cached bytes remain unchanged.
  A synchronization exception also releases the capture guard.
  Relevant code: `Sources/Storage/NotationController.m:658` and `Sources/Storage/NotationController.m:677`.
- The successful retry advances the generation once after these three failures.
  Its independently decoded archive includes the changed syntax metadata.
  Relevant code: `Sources/Storage/NotationController.m:644` and `Sources/Storage/NotationController.m:666`.
- Failed encrypted checkpoint attempts change the live encryption session.
  The earlier completed archive still decodes and restores with its archived settings and password.
  Relevant code: `Sources/Storage/FrozenNotation.m:75` and `Sources/Storage/NVBackupArchive.m:37`.
- Two consecutive restore operations preserve committed source, titles, tags, authored dates, note UUIDs, original source bytes, and source encodings.
  They also preserve pending conversion, its retry flag, conflict origin, and separate syntax metadata for each note.
  The restored notes have no old filenames or journal sequence numbers.
  Relevant code: `Sources/Model/NoteObject.m:1260` and `Sources/Storage/NVBackupArchive.m:69`.
- Source-write and journal-sync failures annotate a complete archive that contains the committed model content.
  A later successful journal sync leaves the checkpoint generation unchanged.
  Relevant code: `Sources/Storage/NotationController.m:685` and `Sources/Storage/NotationController.m:708`.
- Deleting every current note produces an independently readable empty checkpoint.
  The older checkpoint still restores both historical notes.
  Relevant code: `Sources/Storage/NotationController.m:645` and `Sources/Storage/NVBackupArchive.m:74`.

## Limits

The native arm64 fixture uses the existing test UI scaffolding and CommonCrypto AES provider.
It uses the production compression and portable PBKDF2 code.
It does not run the shipping Intel OpenSSL archive.
Three existing compiler warnings concern `foregrndColor` declarations and a `BufferUtils.c` pointer cast.

The fixture replaces primary note writes, journal synchronization, and atomic checkpoint storage with explicit success or failure outcomes.
It does not establish filesystem durability, real source-file retries, journal encoding, password dialogs, browser switching, or application startup.
The copied Intel app stalls before `main` on this host.
No full application lifecycle result is claimed.

The known preference-pane and foreign-owner deletion findings belong to other round 2 reports.
This review adds no production edits or commits.
