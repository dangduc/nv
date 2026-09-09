# Round 2: ownership and interface review

PR: https://github.com/fastducduc/nv/pull/8

This independent review uses an Ousterhout-inspired lens. It does not represent John Ousterhout.
The review focuses on numeric draft lifetime, controller contracts, and restore ownership.

Production baseline: `a89f8351646f824f51ed6ea80b94f724f37d0303`.
The production working tree had no changes during these checks.
Initial feature: `30c3cf816c80e4ff957223d55f22b36074880ef1`.
PR base: `119c453`.
Host: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), arm64.

## Finding

**P2: Closing Preferences does not commit a numeric backup setting.**

Location: `Sources/Preferences/NVBackupPreferencesViewController.m:222`.
Related owner: `Sources/Preferences/PrefsWindowController.m:72`.

Enter a valid Recent value, then close Preferences without leaving the field.
The window closes, but AppKit retains its field editor.
The pane receives no end-edit notification and never commits or schedules the draft.
The window close handler only synchronizes global preferences and closes the font panel.

The native probe entered `321` while the saved value was `96`.
After the close action, the editor remained attached and the pending dictionary held `321`.
The saved value remained `96`, and `commitFieldsWhenIdle` remained false.
The same result occurred during a backup operation and after its completion.
Thus, the closed pane can leave the backup controller with the previous retention policy.

Give the pane and its window owner an explicit close contract.
That contract must finish valid edits or defer them until idle, and preserve invalid input for correction.
A temporary change to end editing in the extracted close handler removes the reproduced failure.
This temporary change establishes the missing lifetime boundary. It is not a complete proposed validation flow.

## Executable evidence

Run these commands from `/Users/duc/dev/nv`.

| Command | Result |
| --- | --- |
| `python3 Tests/BackupReview/round2/ousterhout/run-pane.py` | Exit 0. Passed 17 assertions, including explicit reproduction of the two close failures. |
| `python3 Tests/BackupReview/round2/ousterhout/run-pane.py --expect-fixed` | Exit 1. Failed at `idle close commits valid draft by idle`. |
| `python3 Tests/BackupReview/round2/ousterhout/run-pane.py --expect-fixed --close-mutation` | Exit 0. Passed 15 assertions after the temporary close-handler mutation. |
| `python3 Tests/BackupReview/round1/ousterhout/run-restore.py` | Exit 0. Passed 23 extracted restore-contract checks and rejected three unsafe mutations. |
| `python3 Tests/BackupStore/run-teardown.py` | Exit 0. Passed four extracted teardown assertions and rejected three unsafe mutations. |

The new [pane probe](pane-lifetime.m) executes the complete production pane and native AppKit windows and field editors.
The [runner](run-pane.py) extracts the exact `windowWillClose:` method from the production window owner.
The window is visible before `performClose:` runs. The probe checks that the action closes it.
The reusable coordinator fake records settings and posts status notifications. It does not write defaults or backup files.
The global-preferences fake implements an empty `synchronize` method.

The new assertions also establish these successful boundaries:

- A pane switch commits a valid draft while idle.
- A pane switch preserves a valid draft during work and commits it after completion.
- A rejected deferred policy leaves all saved settings unchanged and preserves both field drafts.
- Correction of the invalid field commits the complete pending policy and clears its drafts.

The temporary mutation inserts `[window makeFirstResponder:nil]` into the extracted close handler.
It only changes a generated file in a temporary directory.
The runner removes its generated sources and binaries after each run.

## Restore review and limits

The restore code preserves the prepared-library boundary and avoids a second commit during successful replacement.
The reused probes check preparation before replacement, rollback after initialization failure, and subordinate teardown ordering.
They also check that the caller receives the rollback error instead of the replacement error.
This review found no new restore-ownership defect within that scope.

The restore probes extract production methods and use call-recording collaborators.
They do not establish complete application startup, browser attachment, or journal behavior.
The pane probe does not load the full Preferences nib or execute the full window controller.
Its native close action and extracted delegate establish the draft-lifetime failure, with the collaborators described above.

No Intel application was launched because the host stalls before application startup.
No personal notes or production source files changed during this review.
