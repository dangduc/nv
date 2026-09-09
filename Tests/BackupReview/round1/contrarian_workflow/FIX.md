# Correction for round 1 workflow finding

Addresses PR #8 comment https://github.com/fastducduc/nv/pull/8#issuecomment-5593824056.

The Backups pane keeps numeric field editors enabled while a backup operation runs.
It stores pending numeric drafts locally and commits completed drafts when the coordinator becomes idle.
An idle notification does not validate or commit a field that the user is still editing.
A library switch discards the previous library's active and deferred drafts.

Back Up Now, Choose Folder, Restore Backup, and Delete Backups validate and save pending numeric fields before forwarding their actions.
Invalid syntax or an out-of-range setting blocks the dependent action and preserves the draft for correction.
A guard prevents reentrant preference notifications from committing fields twice.
No backup coordinator API or disk transaction changed.

Validation:

- `python3 Tests/BackupPreferences/run.py` passed. This now includes real AppKit field editors in a native window.
- `python3 Tests/BackupReview/round1/contrarian_workflow/run.py --negative-mutations` passed the corrected automatic and manual sequences.
  Both negative mutations failed: disabling the active editor, and forwarding Back Up Now without committing numeric drafts.
- A strict production-pane syntax check passed: `xcrun clang -fno-objc-arc -fsyntax-only -Wall -Wextra -Werror -Wno-unused-parameter -mmacosx-version-min=10.13 -I Sources/Application -I Sources/Storage -I Sources/Preferences Sources/Preferences/NVBackupPreferencesViewController.m`.
- `git diff --check` passed for the changed pane and test files.

The native tests cover automatic busy/completion, ending an edit while busy, moving to an unfinished second field before completion, valid and invalid explicit actions, coordinator range rejection, and library replacement with both active and deferred drafts.
They use the production pane with an in-memory coordinator. They do not run the shipping Intel app or filesystem backup engine.

The review probe now checks corrected behavior by default. `--expect-fixed` remains an accepted explicit form.
`--expect-regression` preserves the original assertions for use with the reviewed baseline source; it is expected to fail against the corrected pane.
The original `REPORT.md` records commands and output from the pre-fix baseline.
