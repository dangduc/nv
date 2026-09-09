# Backup archive checks

The desktop probe uses a copied app and disposable notes.
It covers capture generations, checkpoint errors, archive recovery, journal closure, and the application restore coordinator.

After the Development build, run the desktop probe:

```sh
python3 Tests/BackupArchive/run.py
```

The probe includes these checks:

- Captured bytes equal the committed database archive.
- Unchanged captures preserve the checkpoint generation.
- Syntax changes, copied libraries, failed writes, and retries retain the correct generation.
- Source text, original bytes, encoding, byte-order marks, pending conversions, UUIDs, tags, dates, and syntax metadata survive recovery.
- Recovery preserves encryption and rejects incorrect passwords.
- Journal removal failure preserves the open writer.
- A new library cannot recover the active library journal.
- Recovery opens an encrypted archive after the original directory moves away and its journal closes.
- Coordinator failure preserves the original library. Coordinator success attaches the recovered library to its browsers.

## Native offline checks

On Apple Silicon, run the offline checks:

```sh
python3 Tests/BackupArchive/native/run.py
```

This harness compiles the production `NoteObject`, `NotationPrefs`, `FrozenNotation`, `NVBackupArchive`, and `BufferUtils` implementations.
It also uses the production compression methods and portable PBKDF2 implementation.
Test helpers replace UI services. CommonCrypto supplies AES-256-CBC with PKCS7 padding because the bundled OpenSSL library contains Intel code.

These checks cover archive recovery and model metadata.
They do not cover the bundled OpenSSL binary, primary checkpoint writes, journal lifecycle, browser attachment, or the password dialog.
The native harness does not replace the desktop probe.

## Recorded results

On September 8, 2026, the native harness passed 72 checks on macOS 26.5.2 with Xcode 26.6.
The desktop probe produced no startup output before its 120-second timeout.
Its disposable Intel app remained in a kernel wait, consistent with the earlier Rosetta startup failure on this host.
No desktop assertion ran during that attempt.

The benchmark uses about 2 KiB of UTF-8 source per ordinary note and one 5 MiB source note.
Each note also retains its original source bytes.
The benchmark uses plaintext archives.

| Notes | Total source bytes | Archive bytes | Archive capture | Offline restore | Process peak memory |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1,000 | 7,321,261 | 247,596 | 60.43 ms | 126.32 ms | 236.16 MiB |
| 10,000 | 26,041,261 | 1,995,139 | 363.82 ms | 657.97 ms | 1,000.09 MiB |

Capture time measures `FrozenNotation` serialization and compression.
Restore time measures archive decoding, identity reset, and serialization of the recovered archive.
These times exclude fixture creation, primary database checks, disk writes, and UI work.
Peak memory records the cumulative process maximum from `getrusage`.
The two benchmark cases run in one process, with a separate autorelease pool for each case.
