# Source storage regression checks

Run these checks after a Development build:

```sh
python3 Tests/Regression/source-storage/run.py
```

The suite uses a copied application, isolated settings, and temporary notes.
It checks source characters, line endings, encoding, byte order marks, original bytes, and explicit UTF-8 conversion.
It checks local syntax metadata across rename, sync updates, library archives, and library isolation.
It checks actual file writes, source exports, and the library archive on disk.
It checks that canceled conversion survives reopening and retries without changing the source file.
File metadata events must preserve the edited source until conversion succeeds.
External body changes must survive in a separate note, both before and after directory notification delivery.
The probe reads the real recovery journal before the original file write to check that the external version is already recoverable.
Pending conversion blocks Text Encoding in the sheet predicate and model API.
Conversion offers check the exact live note before scheduling, presentation, and acceptance.
Deletion, a new note with the same filename, and deletion Undo cannot revive an obsolete offer.
Conflict synchronization failures reuse one copy per external version, including after archive recovery.
The retry fixtures retain separate CP-1252 and UTF-16 versions and check the journal before the original source replacement.
UTF-8, UTF-16, and UTF-32 fixtures distinguish a transport BOM from a literal leading U+FEFF, including after edits.
Encoding fixtures compare source characters with the legacy MacRoman decoder, alongside explicit CP-1252 and UTF-8 controls.
An archived GB18030 byte alias must retain its original bytes in source export and conflict-copy matching.
Source bytes stay inside note archives, which follow library encryption.
It also checks the removal of rich-text imports, storage, and exports.
No fixture starts a network request.

The fixtures inspect Simplenote request data without sending it.
They do not promise source fidelity through the existing Simplenote service.
