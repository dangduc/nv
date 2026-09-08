# Round 1: state ownership and abstraction boundaries

This review uses a John Ousterhout-inspired perspective. It does not represent a review or statement by John Ousterhout.

No actionable regression was found in this scope at `162c872`, compared with `b27af28`.

The native probe passed 39 checks against the frozen PR app. The probe used two browser windows, one shared library, and disposable notes.

The checks covered these contracts:

- A shared visibility callback commits a pending Title or Tags edit to the original peer note.
- The initiating browser retains its selection and note metadata.
- Each hidden field releases its native editor and metadata target.
- Undo and Redo retain the metadata edit as one note operation.
- Two windows can retain independent Title and Tags editors for the same note.
- A Title commit preserves the pending peer Tags editor during model notification reentry.
- An untouched Title field in Preview transfers focus to the loaded native viewer.
- Visibility changes preserve both source strings and the number of notes.

`layoutNoteHeader` delegates metadata changes through `commitNoteMetadata`. That method clears its editing target before model callbacks run. The native reentry probe supports this boundary.

## Commands and evidence

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/ViewControlsReview/round1/ousterhout/checks.inc \
  --app build/ViewControlsReview/round1/nvALT.app
```

The command returned 0. `results.log` ends with `OUSTERHOUT REVIEW PASSED: 39 checks`.

The mutation control replaced `commitNoteMetadata` with a no-op in the disposable process:

```sh
NV_REVIEW_DROP_METADATA_COMMIT=1 python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/ViewControlsReview/round1/ousterhout/checks.inc \
  --app build/ViewControlsReview/round1/nvALT.app
```

The command returned 1. `negative-control.log` records the failure at `a shared hide commits the peer field to its original note`.

The mutation did not change production files or the app bundle.

## Limits and fixture correction

The probe used macOS 26.5.2 and the Intel Development app under Rosetta. It did not exercise a physical input method or restoration after relaunch.

The first fixture inherited its injected test library into MultiMarkdown. The helper then failed because it lacked the application classes.
The final probe removes `DYLD_INSERT_LIBRARIES` before helpers run. It requires a loaded, visible viewer before the Preview focus assertion.
The helper failure was a fixture error and is not a PR finding.
