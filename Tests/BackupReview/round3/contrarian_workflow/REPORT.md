# Round 3: contrarian workflow review

PR: https://github.com/fastducduc/nv/pull/8

Production baseline: `8ebbcb511415958f700ca54e4216e6447464d284`.
PR base: `119c453`.
Host: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), arm64.

**No new actionable finding within this focused scope.**

This review challenges the Preferences pane transition and error recovery workflow.
The new probe runs the production `switchViews:` method instead of the simplified pane replacement from round 2.
It also runs the production close delegates and the complete Backups pane.

The earlier workflow and Ousterhout reports identified draft loss and the missing close contract.
The round 3 baseline contains those corrections.
This review found no additional defect in the transitions described here.

## Executable evidence

Run these commands from `/Users/duc/dev/nv`.

| Command | Result |
| --- | --- |
| `python3 Tests/BackupReview/round3/contrarian_workflow/run.py` | Exit 0. Passed 33 new assertions. |
| `python3 Tests/BackupReview/round3/contrarian_workflow/run.py --negative-mutations` | Exit 0. Passed 33 assertions and rejected both temporary mutations. |
| `git diff --check -- Tests/BackupReview/round3/contrarian_workflow` | Exit 0. |

The [runner](run.py) extracts the current switch method, scaling function, and close delegates on each run.
It compiles these methods with the [native probe](probe.m) and the complete production Backups pane.
Each compilation and executable has a 30-second timeout.
The runner removes its generated sources and binaries after completion.
Default execution requires the current expected behavior.

The probe establishes these results:

- Closing Preferences before the first Backups visit does not create the pane.
- The first Backups action creates the pane with its intended native content dimensions.
- Reselecting Backups ends the native field edit and preserves the draft. A busy coordinator defers the save until idle.
- A hidden pane retains both an operation error and a draft error after worker completion. The completion opens no error dialog.
- An invalid hidden policy leaves the complete saved policy unchanged.
- A rejected close reveals Backups through the production switch method. The window title, toolbar selection, and saved pane identifier agree.
- The rejected close reports one error and selects the complete invalid draft.
- Correction saves the complete policy before close. It clears the draft error and retains the operation error.
- Reopening the saved Backups pane displays a status change that arrived while the window was closed.
- A library notification clears a hidden deferred draft. Returning from Notes displays the new library policy, schedule state, and status.

The negative mutations suppress hidden status refresh and discard the operation error during a draft error.
Both fail at `Hidden status retains operation and draft errors together`.
These mutations affect temporary copies only.

## Source boundaries

| Source | Reviewed contract |
| --- | --- |
| `Sources/Preferences/PrefsWindowController.m:72` | Rejected close reveals and focuses the invalid Backups field. |
| `Sources/Preferences/PrefsWindowController.m:522` | Pane selection, content replacement, dimensions, and saved pane identity. |
| `Sources/Preferences/NVBackupPreferencesViewController.m:141` | Hidden status refresh, draft lifetime, and library identity. |
| `Sources/Preferences/NVBackupPreferencesViewController.m:198` | Operation errors and draft errors remain visible together. |
| `Sources/Preferences/NVBackupPreferencesViewController.m:328` | Draft preparation before window close. |

These references identify reviewed boundaries. They are not findings or severity assignments.

## Evidence limits

The probe uses native AppKit windows, toolbars, field editors, content replacement, and close actions.
Toolbar actions use `NSApplication sendAction:to:from:`. The probe does not generate physical mouse clicks.
The owner contains extracted production methods. It does not load the full Preferences nib or run the complete Preferences controller.
General, Editing, and Notes use empty native views. Global preferences use memory storage and an empty synchronization method.

The reused backup coordinator fixture stores settings in memory and posts status notifications.
The probe supplies operation status, busy transitions, and the library replacement notification.
The library change establishes draft isolation after a notification. It does not establish a menu path through a restore password dialog.
Error presentation records calls without a modal dialog.
The probe does not run a backup worker, decode an archive, or replace a notes library.

AppKit emitted XPC connection messages during execution. The production probe completed all 33 assertions with exit 0.
The Intel application stalls before `main` on this host. This review did not launch that application or establish full desktop integration.
No production source, personal notes, or nvALT settings changed during this review.
