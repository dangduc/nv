# Round 1: State Consistency Review

Perspective: an AI review using Kyle Kingsbury's state-consistency and failure-sequence lens, not a statement by Kyle Kingsbury.

Production reviewed: `10de8a4` against `116daff`. HEAD `8d744e2` only adds review screenshots and documentation. Tests loaded an injected probe into a copy of the existing Development app. No production files changed.

## Findings

No new actionable finding in the three tested histories. All 23 assertions passed, including six temporary-library setup checks.

| History | Expected and observed result | Output |
| --- | --- | --- |
| Start composing a replacement search query, then invoke New Note | Exactly one blank note is created and selected. The query stays empty after the old field editor ends composition. Focus moves to the new title. | `search-new.log`: 8 checks passed |
| Start a marked title edit, delete that note through the library, then select another note | The deleted note remains absent. The replacement note keeps its original title. The old field editor has no marked text. | `delete-metadata.log`: 6 checks passed |
| Leave a title edit pending, then switch the shared library while two browsers exist | The old note receives its pending title. Both browsers attach to the new library. The old field session does not modify or copy a note into that library. | `switch-library.log`: 9 checks passed |

Relevant implementation: `AppController_BrowserUI.m:160-182` binds and commits metadata to its original note; `AppController_BrowserUI.m:205-213` handles New Note; `NVApplicationController.m:131-147` finishes browser edits before switching libraries.

## Reproduction

Run each command from the repository root:

```sh
NV_REVIEW_CASE=search-new python3 Tests/NativeUIReview/round1/kingsbury/run.py
NV_REVIEW_CASE=delete-metadata python3 Tests/NativeUIReview/round1/kingsbury/run.py
NV_REVIEW_CASE=switch-library python3 Tests/NativeUIReview/round1/kingsbury/run.py
```

The runner serializes GUI access with `build/pr-review/gui.lock`, changes the copied app's bundle identifier, and uses temporary notes and defaults. The probe skips sync service startup and external editor initialization.

## Limits

These are deterministic AppKit composition calls, not a physical input-method session. Deletion enters through the shared model; it does not exercise a remote sync transport. The library-switch probe follows the preference flow's flush-and-close-journal step. An earlier harness version omitted that step and recovered the old journal into the new library; that harness error is excluded from the findings.

The existing AppKit layout-recursion warning appears at startup. This review did not investigate it. The known metadata Undo routing and removed Search toolbar item findings are outside these tests.
