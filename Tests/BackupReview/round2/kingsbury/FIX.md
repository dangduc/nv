# Round 2 correction: keep journal recovery modal

This correction addresses the P1 finding in [REPORT.md](REPORT.md).
The reviewed application returned to its original library after both replacement initialization and journal rollback failed.
Later database edits lacked a recovery journal.

The application now keeps the restore transition active until exclusive journal initialization succeeds.
A modal dialog offers Retry and Quit after a failed resume.
Each retry preserves an occupied journal without reading or deleting its records.
A canceled Quit or a thrown exception returns to the recovery dialog.
After termination starts, a failed termination permits only another Quit attempt.

The command guard remains active through replacement attachment and preference callbacks.
It rejects forwarded commands, metadata changes, new windows, activation, reopen requests, file opens, URL events, and Services requests.
File opens, URL events, and Services requests report failure to their callers.
Normal forwarding resumes after journal recovery.
Termination permits browser checkpoint calls only during the termination callback, with an exception-safe reset of that permission.

Replacement initialization exceptions also enter recovery.
Recovery logs contain fixed messages without exception descriptions or note content.
The external-content preservation callback retains its existing behavior.

ODB editor events reach note objects directly.
Restore preparation therefore refuses to close the journal while a library note has an active ODB session.
The refusal preserves callback registrations and temporary files.
The session check follows checkpoint capture and precedes checkpoint synchronization and journal closure.
After the final external save and close, restore can proceed with the latest content.

## Validation

The native probes use macOS 26.5.2 (25F84), Xcode 26.6 (17F113), and arm64.
The recovery and ODB probes compile with `-Wall -Wextra -Werror` and explicit exclusions for legacy API warnings.

```sh
python3 Tests/BackupReview/round2/kingsbury/run.py
python3 Tests/BackupReview/round2/kingsbury/run.py --baseline
python3 Tests/BackupReview/round2/kingsbury/run-odb-preflight.py
python3 Tests/BackupReview/round1/ousterhout/run-restore.py
python3 Tests/BackupStore/run-teardown.py
```

The recovery probe passes 60 assertions in the control process and 60 assertions after a replacement initializer exception.
It covers persistent journal contention, Retry, canceled Quit, termination exceptions, panel exceptions, and journal initialization exceptions.
The probe checks blocked commands, external events, and Services requests during recovery.
It permits a checkpoint inside the termination callback and rejects commands after that callback throws.
Secret-bearing fixture exceptions do not appear in the captured logs.

The abrupt-exit process leaves the later edit in the recovery journal.
The parent process reads those journal bytes after the child exits without cleanup.
The baseline mode still reproduces the reviewed failure with 29 control assertions and 22 assertions before abrupt exit.

The ODB probe passes 21 assertions.
It exercises the extracted session query, event dispatch, note callbacks, and restore preparation.
It covers a session registered during checkpoint capture, intact temporary files, later journal writes, and restore after the last session closes.
Removing the session guard fails the expected preparation assertion.

The earlier restore contract passes 26 assertions and rejects three unsafe mutations.
Its recovery panel and application termination endpoint are fixtures.
The teardown contract passes four assertions and rejects three unsafe mutations.
It covers ordinary commits and prepared teardown without later commits.

## Limits

The recovery probe extracts production application and storage methods.
Its note model, archive encoder, preferences, replacement initializer, and UI are fixtures.
Its journal uses exclusive file creation, writes, synchronization, and unlink operations on disposable files.
The ODB probe uses extracted production callbacks with fixture note decoding and journal persistence.

These probes do not run the shipping journal encryption, compression, OpenSSL archive, or startup decoder.
They do not establish full-application recovery behavior or validate the visible modal dialog.
The Intel application remains stalled before `main` in this environment.
No additional Intel application launch forms part of this correction.
