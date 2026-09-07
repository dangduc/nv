# Round 2: Abstraction and ownership

This AI review uses a John Ousterhout-inspired perspective on abstraction, ownership, and complexity. It does not represent his participation or views.

Reviewed production revision: `12936fed78e1d98ac646bb88b51e009609ad505e`.
Comparison baseline: `116daff`.
Environment: macOS 13.7.8 (22H730), Xcode 15.2 (15C500b).

## Result

No actionable finding in the three bounded cases. The independent probe passed 44 assertions, including its setup and native activation assertions.

The separate metadata target preserves history when an external body snapshot clears text history. The normal library replacement path removes its undo actions before release.

## Scope

- `NVNoteEditingSession.m:15-31`, `:241-258`, and `:300-315`: the borrowed session pointer, metadata history, and teardown.
- `NVApplicationController.m:131-147`, `:172-182`, and `:201-210`: library replacement, browser closure, and cached session ownership.
- `AppController_BrowserUI.m:160-193`: metadata editing and commit boundaries.
- `AppController.m:1160-1183` and `:1760-1767`: editor attachment and browser closure.

The probe extends the existing copied-app harness with new cases. It does not rerun the acceptance suite.

## Command and isolation

```sh
python3 Tests/NativeUIReview/round2/ousterhout/run.py
```

The runner acquires `build/pr-review/gui.lock` and compiles an x86_64 probe library. It uses the supplied Development app without a production rebuild.

The runner copies that app into a temporary directory and assigns a unique bundle identifier. Notes, application support, and temporary files stay in that directory.

The injected harness bypasses normal launch actions, external editor initialization, and sync startup. It opens both test libraries in temporary directories.

The runner uses this Launch Services form, with absolute temporary paths:

```text
open -W -n --stdout <log> --stderr <log>
  --env NV_WINDOW_TEST_DIRECTORY=<root>
  --env DYLD_INSERT_LIBRARIES=<probe.dylib>
  --env TMPDIR=<root>/Temp/
  <copied.app> --args -ShowDockIcon YES -StatusBarItem NO
  -QuitWhenClosingMainWindow NO -SUEnableAutomaticChecks NO
```

The launch has a 90-second timeout. The runner removes its unique defaults domain after the app exits.

Every responder action requires actual AppKit application activation, key-window state, and main-window state. The probe also checks the coordinator's active browser.

## Expected and actual results

| Case | Expected | Actual |
| --- | --- | --- |
| Metadata redo after detachment | Tag redo survives an external body snapshot without attached editors. | Passed. The session had zero layout managers. Redo restored tags and preserved the external body. |
| Last browser closure | A new browser can use the earlier metadata history. | Passed. The browser count changed from zero to one. Native responder redo restored the tags. |
| Unchanged title commit | Committing the current title preserves pending redo. | Passed. Redo remained available and restored the tags. |
| Pending title during library replacement | The old note receives its pending title. The new library gets no old history. | Passed. The old title committed, both history directions cleared, and the new header cleared. |
| Normal session teardown | The old session and its metadata target release after replacement. | Passed. Both deallocation counters reached one. |
| New library history | Metadata undo works independently in the replacement library. | Passed. Native undo restored the new note's original title and preserved its body. |

The library replacement fixture flushes the old library and closes its journal before constructing the replacement. It then calls the normal coordinator replacement method.

The lifetime observation adds a `dealloc` override only to the metadata target class. It does not replace the inherited `NSObject` implementation.

Selected output from `run.log`:

```text
NATIVE READY active=1 key=1 main=1
PASS: an external body snapshot preserves metadata Redo without an attached editor
PASS: the reopened browser redoes metadata and preserves the external body snapshot
PASS: an unchanged title commit preserves pending metadata Redo
R2 OWNERSHIP sessionDeaths=1 targetDeaths=1 oldUndo=0 oldRedo=0
PASS: normal library replacement releases the old session and its borrowed-session undo target
PASS: the replacement library owns a separate working metadata history
OUSTERHOUT ROUND2 PASSED (44 checks)
```

## Baseline distinction and limits

Source comparison shows that `116daff` lacks this metadata target and the native metadata header. The probe ran against the supplied corrected app only.

This report makes no runtime baseline equivalence claim. The existing application session cache remains outside this review's memory-growth scope.

Three initial direct-executable launches failed the native activation prerequisite before the behavioral cases. Their logs show no product finding.

The final runner uses Launch Services. The successful run established actual foreground state without changing the coordinator's active-browser state directly.

The external body update uses the model API. It does not use a live sync account, physical keyboard input, or an external editor application.

The run still emitted the existing AppKit layout-recursion warning. These cases do not establish its cause or user impact.

This review covers one last-window reopen and one library replacement. It does not claim broader lifecycle coverage.
