# Preferences window close correction

Finding: [posted P2](https://github.com/fastducduc/nv/pull/8#issuecomment-5593991020).
Review baseline: `a89f8351646f824f51ed6ea80b94f724f37d0303`.
The correction is in the working tree. This agent created no commit.

The Preferences window now asks the Backups pane to prepare its drafts before closing.
The pane checks all pending fields, including fields in a hidden pane.
Valid fields save immediately while idle. During a backup operation, they remain pending and save after completion.
The pane ends the field editor before a successful close.

Invalid input keeps the window open. The window reveals Backups, shows the field-specific error, and selects the invalid input.
Numeric checks include the allowed ranges before a busy close can defer the policy.
This prevents a closed window from accepting input that fails only after the worker finishes.

Status notifications no longer show validation dialogs.
A deferred validation failure preserves the draft and adds an explanation to the pane status.
A later close attempt reveals the invalid field for correction.
A library switch clears old drafts, deferred-save state, and the field error.
Existing manual actions still require a successful field commit before forwarding the action.

## Checks

Run these commands from `/Users/duc/dev/nv`.

| Command | Result |
| --- | --- |
| `python3 Tests/BackupReview/round2/ousterhout/run-pane.py` | Passed 89 assertions. Corrected assertions are the default. |
| `python3 Tests/BackupReview/round2/ousterhout/run-pane.py --negative-mutations` | Passed 89 assertions and rejected the skipped close contract. |
| `python3 Tests/BackupPreferences/run.py` | Passed settings, numeric input, stale-library, busy/edit/action ordering, action routing, and pane layout checks. |
| `python3 Tests/BackupReview/round1/contrarian_workflow/run.py --negative-mutations` | Passed automatic and manual draft checks. Rejected editor-discard and skipped-manual-commit mutations. |
| `xcrun clang -fsyntax-only -fno-objc-arc -Werror -mmacosx-version-min=10.13 -I Sources/Application -I Sources/Storage -I Sources/Preferences Sources/Preferences/NVBackupPreferencesViewController.m` | Passed with warnings treated as errors. |

The expanded native probe covers all four numeric upper or lower bounds during idle and busy close attempts.
It checks hidden invalid drafts, worker completion before and after a rejected close, correction without duplicate errors, and a library switch.
It also checks valid busy closes, valid pane switches, and atomic policy changes.

The probe compiles the complete production pane and extracted `windowShouldClose:` and `windowWillClose:` methods with `-Werror`.
The existing fake class implementations retain their incomplete-implementation warning exception.
Native AppKit handles visible windows, close actions, and field editors.
The pane-switch collaborator changes native content views, but it does not run the complete Preferences toolbar controller.
Error presentation records calls without a modal dialog. No probe opens a notes library or writes application settings.

The host emitted AppKit XPC connection messages during the native close probe. The assertions completed and returned exit 0.
Full Intel application startup remains outside this evidence because the host stalls before application startup.
