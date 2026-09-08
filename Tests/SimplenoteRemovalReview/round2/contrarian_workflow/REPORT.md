# Round 2: workflow compatibility skeptic

No actionable defect introduced by PR #7 was found in this scope.

This review tests the remaining Storage and Security workflows after Simplenote removal. The production revision is `f38a8cb`; the PR base is `9693356`.

## Evidence

The current application passed **54 native checks**. The baseline passed the same workflow checks and one adapter assertion: **55 checks** total.

The probe opens the actual Preferences window and Notes pane. It uses the converted native tabs, control connections, and application controller actions.

The storage popup sends its connected action. Encryption and sheet buttons use `performClick:`. The mismatch and file-cleanup sheets are real AppKit sheets.

The test covers these histories:

1. Database storage changes to individual text files. The resulting UTF-8 file preserves the source, including non-ASCII characters.
2. Cancel on the cleanup sheet retains individual-file storage and exact file bytes.
3. Keep Files changes to database storage and retains exact file bytes. The individual-file extension controls become disabled.
4. The database encryption button calls the picker with the correct preferences window and callback delegate. Picker cancellation leaves encryption disabled.
5. Cancel on the encryption mismatch sheet leaves file storage unchanged and queues no picker.
6. Accepting the mismatch opens the cleanup sheet. The picker remains deferred while that choice is pending.
7. Cancel on cleanup does not show the picker or alter source files. A later encryption request can complete through Keep Files.
8. The retained invocation then calls the picker once, after the database conversion. The controller clears its pending invocation slot.
9. Canceling that picker leaves encryption disabled. Closing Preferences leaves both browsers alive over the same library.

Throughout these histories, the model and both source editors retain the exact source. The individual note file retains its captured bytes.

See [checks.inc](checks.inc), [prefix.h](prefix.h), and [output.txt](output.txt).

## Test boundaries

`SWPicker` replaces passphrase-picker presentation and supplies its cancellation callback. This observes the actual queued invocation without creating a password or opening the real passphrase sheet.

The native preference controllers, storage model, file writes, cleanup sheets, and invocation recorder run without substitutions.

`currentKeychainItem` returns an empty test result throughout the workflow. No password is entered or stored. The test selects neither Move to Trash nor keychain removal.

All notes and file paths belong to the runner's disposable directory. The runner copies the application and isolates its preferences.

## Baseline and sensitivity controls

The baseline is `build/SyntaxFlickerReview/fix.app`, built at `65e1608`. The relevant implementations have no differences from PR base `9693356`:

```sh
git diff 65e1608 9693356 -- \
  Sources/Preferences/NotationPrefsViewController.m \
  Sources/Preferences/NotationPrefs.m \
  Sources/Storage/NotationController.m \
  Sources/Utilities/InvocationRecorder.m
```

The baseline has a known, unsupported popup `removeItem:` call during Notes pane loading. A baseline-only adapter forwards that call to the popup menu.

The adapter permits workflow comparison past that pre-existing crash. It does not change storage, encryption, or invocation behavior. The baseline also expects its original three tabs.

Both applications retained a queued picker invocation after cleanup was canceled. The next encryption request replaced that invocation and completed successfully.

That retained queue is a pre-existing observation. This test does not cover an unrelated storage action after cancellation.

See [baseline-output.txt](baseline-output.txt). It contains the same successful workflow sequence and cancellation observation.

The sensitivity control replaces `runQueuedStorageFormatChangeInvocation` with a no-op in the copied current application. It fails at the expected deferred-picker assertion.

See [mutation-output.txt](mutation-output.txt), which exited 1. The unmodified application exited 0.

## Fixture correction

The first run compared a filesystem-resolved path with an unresolved temporary-directory path. That assertion failed before the sheet histories began.

The fixture now resolves symlinks on both paths before checking containment. The original output remains in [initial-path-fixture.txt](initial-path-fixture.txt).

## Reproduction

Run from the repository root:

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/SimplenoteRemovalReview/round2/contrarian_workflow/checks.inc \
  --prefix Tests/SimplenoteRemovalReview/round2/contrarian_workflow/prefix.h \
  --app build/SimplenoteRemovalReview/round1.app
```

For the baseline comparison, set `NV_SW_BASELINE=1` and use `--app build/SyntaxFlickerReview/fix.app`.

For the sensitivity control, set `NV_SW_DROP_QUEUED_PICKER=1` and use the current application. Expect exit 1 at the deferred-picker assertion.

The runner serializes desktop access through `build/pr-review/gui.lock`.

## Limits

This review covers the English interface and native action dispatch. It does not simulate physical keyboard or pointer input.

It does not test successful passphrase entry, encryption cryptography, encrypted restart, password changes, or keychain persistence. The real passphrase sheet is not loaded.

The file checks compare one disposable note throughout storage transitions. They do not test every encoding, filesystem failure, or concurrent external file change.

No production change is proposed from this review.
