# Backup store checks

Run these checks on macOS with Xcode:

```sh
python3 Tests/BackupStore/run.py
python3 Tests/BackupStore/run-teardown.py
```

The runner compiles the production `NVBackupStore.m` with Foundation and temporary fault hooks.
It uses native architecture and disposable files. It does not open nvALT or access an existing notes library.

The checks cover:

- Exact archive bytes, manifest fields, SHA-256 checks, and private file permissions.
- Invalid manifest fields, excessive archive sizes, corrupt archives, and unexpected package contents.
- Symbolic links, destination ownership, unrelated files, foreign snapshots, and concurrent publication locks.
- Partial writes, disk-full errors, permission errors, failed synchronization, failed publication, and failed retention.
- Process interruption during archive writes, before publication, and after publication.
- Recovery after interrupted ownership creation and cleanup of abandoned stages owned by the library.
- Retention across UTC days and Monday-based weeks, with a fixed clock.
- Preservation of the newest committed generation after a backward clock change.
- The storage target, the minimum of three snapshots, and explicit deletion of plaintext history.
- Restore writes into empty folders, with private permissions, exclusive publication, and cleanup after a write failure.
- A selected backup root that disappears between the initial check and the worker write.
- A different directory at the selected mountpoint, detected through the captured device and inode.

Publication synchronizes both files and the staging directory before an exclusive atomic rename.
It then synchronizes the destination directory before retention starts.
A failure at the final directory synchronization leaves the complete package available, but the caller receives an error.
A retention failure returns the completed snapshot and a separate `retentionError`.

The store accepts archives of at most 512 MiB. It does not decode note archives or ask for passwords.
The restore controller owns those checks. Encryption tests for note content belong to the archive and restore suites.

The process-interruption checks preserve real files at the chosen interruption point.
They do not simulate a power cut, device cache loss, or physical storage damage.
Filesystem synchronization requests depend on the operating system, filesystem, and device.

The teardown check compiles the production editor and session methods with call-count fixtures.
It checks that a prepared restore detaches old editors without another commit, including callbacks from table deselection.
Three mutations establish that the checks reject a second session commit, a second editor commit, and early table deselection.
These fixtures do not open native windows or exercise the complete library switch.
