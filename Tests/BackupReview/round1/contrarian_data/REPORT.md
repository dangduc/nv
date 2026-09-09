# Round 1 — contrarian data-safety review

Reviewed PR #8 at `30c3cf816c80e4ff957223d55f22b36074880ef1` against `119c453`.
This review challenges preservation and recovery claims. It does not represent an external reviewer.

No new actionable finding was confirmed in this bounded review.

The probe calls the production `NVBackupArchive`, `FrozenNotation`, `NotationPrefs`, and `NoteObject` implementations.
It checks the following contracts:

- Source recovery preserves CRLF, Unicode, original bytes, and exact export bytes for six encodings.
  The UTF-8, UTF-16 LE/BE, and UTF-32 LE/BE cases run with and without their BOM.
  The MacRoman case has no BOM. Syntax metadata keeps its association with the note UUID.
  Relevant code: `Sources/Model/NoteObject.m:1260` and `Sources/Storage/NVBackupArchive.m:69`.
- Password rotation leaves old snapshots readable with the old password and new snapshots readable with the new password.
  Both wrong-password combinations fail. Reading the old archive twice leaves its input bytes unchanged.
  Relevant code: `Sources/Storage/NVBackupArchive.m:39` and `Sources/Preferences/NotationPrefs.m:292`.
- Enabling encryption leaves the previously captured plaintext archive unencrypted, as the documentation states.
  The restored preferences disable password storage in the keychain.
- A normal archive containing the same note object twice fails the duplicate-identity check before preparing a restored library.
  Relevant code: `Sources/Storage/NVBackupArchive.m:63`.

## Executable evidence

From the repository root:

```sh
python3 Tests/BackupReview/round1/contrarian_data/run.py
```

Result: **107 checks passed**, exit status 0.
The local output is `build/review-r1-contrarian-data.log`.
The runner writes its binary and temporary compilation inputs under `build/BackupReview/round1/contrarian_data/`.

## Limits

This is an arm64 native offline harness. It uses the existing test UI scaffolding and CommonCrypto AES provider.
It does not execute the shipping Intel OpenSSL library, password dialogs, application startup, journals, browser switching, or restore-folder failure handling.
The copied Intel app stalls before `main` on this host, so this review does not claim full application recovery validation.
No encrypted-format security assessment is claimed. The fixtures check functional compatibility and preservation.
