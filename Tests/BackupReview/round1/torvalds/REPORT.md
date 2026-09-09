# Round 1: low-level correctness review

Review lens: Linus Torvalds-inspired attention to resource lifetime, filesystem behavior, and contracts. This is an agent review, not a review by Linus Torvalds.

Baseline: `30c3cf816c80e4ff957223d55f22b36074880ef1`, compared with `119c45302123c14d02dd0c9b620709bf68e6f086`.

## Result

No new actionable defect was confirmed in this review scope.

The filesystem store closes its descriptors on the tested success and failure paths. Failed publication and partial restore preserve the complete backup that existed before the operation. Lock contention leaves the destination unchanged. Retention preserves the sole complete package even when the storage target is smaller than that package.

The new `initWithDirectoryRef:error:` failure releases also agree with current callers. Startup autoreleases only the returned object. Normal folder replacement and backup restore release the replacement only on success. Alias and default-folder initializers assign the delegated result to `self`; neither releases it again on failure. This caller audit is source inspection, not full application execution.

Reviewed locations include:

- `Sources/Storage/NVBackupStore.m:195`: exclusive file writes and close handling.
- `Sources/Storage/NVBackupStore.m:324`: per-package autorelease pools during enumeration.
- `Sources/Storage/NVBackupStore.m:343`: bounded package deletion.
- `Sources/Storage/NVBackupStore.m:472`: publication and retention error paths.
- `Sources/Storage/NVBackupStore.m:574`: failed restore cleanup.
- `Sources/Storage/WALController.m:96`: preserving the writer on unlink failure.
- `Sources/Storage/NotationController.m:161`: restored initializer ownership.
- `Sources/Storage/NotationController.m:181`: delegated initialization failures.
- `Sources/Browser/AppController.m:338`, `:371`, and `:838`: initializer callers.
- `Sources/Application/NVApplicationController.m:248`: restore caller ownership.

## Executable evidence

Command:

```sh
python3 Tests/BackupReview/round1/torvalds/run.py
```

Result:

```text
PASS: 691 checks; 140 injected publication failures, 20 real lock-contention failures, 20 partial-restore failures; descriptor count 3 -> 3
```

The driver compiles the production `NVBackupStore.m` with manual memory management, native Foundation, and `-Wall -Wextra -Werror`. It uses the existing test-only failure hooks. The new probe uses disposable local files and `proc_pidinfo` to count open descriptors after every failure. A real `flock` supplies the contention case. No production source was changed.

## Limits

These checks run on the host architecture. They do not launch the Intel app, run its OpenSSL binary, or exercise Cocoa window replacement and journal recovery together. Descriptor counts do not establish absence of heap leaks. The probe does not simulate power loss, remote filesystem behavior, or concurrent external file mutation.
