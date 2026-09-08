# Round 2: local external editing and source export

This review uses a Linus Torvalds-inspired perspective. It does not represent his participation or endorsement.

No actionable defect was found in the reviewed change.

The production comparison is PR #7 revision `f38a8cb` against base `9693356`. Subsequent review commits do not change application production code.

## Scope and source review

The review follows the local paths that previously also notified sync services:

- `NoteObject` receives an ODB file-change callback, reads source bytes, schedules a local write, and notifies the library delegate.
- `NotationDirectoryManager` detects changed source files and updates the note and its visible editors.
- `NotationController` persists those changes through local file and database writes.
- Source export writes the note's retained bytes and encoding through `NoteObject`.

The diff removes remote-service calls while keeping these local operations. The examined paths have no remaining calls to the removed remote selectors.

## Native evidence

[checks.inc](checks.inc) runs inside a copied application with a disposable library. [prefix.h](prefix.h) declares imports and one optional sensitivity-control method.

The fixture opens three browser windows. Two display the same note through shared source storage. The third displays an unrelated note.

The probe executes these histories:

1. Write a temporary UTF-8 BOM source file. Invoke the real ODB model callback while the library uses database storage.
2. Switch to separate plain-text files. Save a UTF-16 little-endian BOM source through a second ODB callback, then flush the backing file.
3. Modify that backing file through an independent local write. Invoke the real directory reconciliation method and verify the changed source.
4. Insert text through a native source editor after reconciliation. Flush and verify the subsequent local write.
5. Invoke the ODB close callback. Verify that it removes the temporary file and preserves the backing file.
6. Decode the written library snapshot. Verify two notes remain and the edited note retains its UUID, exact source, and encoding bytes.

At each source update, the probe checks exact model content, both editor strings, shared storage identity, bounded selections, separate search queries, and selected note identity. It also checks local syntax, the original title, and the untouched third window.

Four actual source exports must match the expected bytes, including their BOMs and line endings. Each export then attempts a prohibited overwrite. The existing exported bytes must remain unchanged.

[output.txt](output.txt) records **82 passing native checks** for the removal build. [baseline-output.txt](baseline-output.txt) records the same **82 passing checks** against the production-equivalent pre-removal build.

The probe uses selectors and KVC for application state. It does not assume current private ivar offsets when testing the older binary.

## Sensitivity control

[check-mutation.py](check-mutation.py) runs a separate copied application. It replaces the ODB file-change callback with a no-op inside that process only.

[mutation-output.txt](mutation-output.txt) records the expected native failure:

> FAIL: external update commits the exact source in the note model

The control script succeeds only when this exact assertion fails. Production files remain unchanged.

## Fixture correction

[initial-fixture-output.txt](initial-fixture-output.txt) preserves the first run. A path assertion compared `/var` with `/private/var` without resolving their symlink relationship.

The corrected probe resolves both paths before checking that the backing file belongs to the disposable library. Its diagnostic confirms identical file bytes. Both production and baseline runs then pass.

## Reproduction

Run from the repository root in an active macOS desktop session:

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/SimplenoteRemovalReview/round2/linus/checks.inc \
  --prefix Tests/SimplenoteRemovalReview/round2/linus/prefix.h \
  --app build/SimplenoteRemovalReview/round1.app

python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/SimplenoteRemovalReview/round2/linus/checks.inc \
  --prefix Tests/SimplenoteRemovalReview/round2/linus/prefix.h \
  --app build/SyntaxFlickerReview/fix.app

python3 Tests/SimplenoteRemovalReview/round2/linus/check-mutation.py
```

The runs used macOS 26.5.2 and Xcode 26.6, with an Intel application under Rosetta. The runner serializes desktop probes with the shared GUI lock.

## Limits

The probe directly invokes ODB callbacks. It does not launch an external editor or test the Apple event transport, editor discovery, or an external rename callback.

Directory monitoring is stopped before the independent file write. The test invokes reconciliation explicitly, so it does not establish notification-delivery timing.

The fixture has no pending input composition or concurrent local edits during external replacement. It does not test conflict copies, disk failures, crash durability, or network behavior.

Snapshot recovery decodes the written archive in the running process. This review does not claim a second-process restart test or verify exported Finder tags and dates.
