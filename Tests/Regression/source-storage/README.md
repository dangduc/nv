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
Source bytes stay inside note archives, which follow library encryption.
It also checks the removal of rich-text imports, storage, and exports.
No fixture starts a network request.

The fixtures inspect Simplenote request data without sending it.
They do not promise source fidelity through the existing Simplenote service.
