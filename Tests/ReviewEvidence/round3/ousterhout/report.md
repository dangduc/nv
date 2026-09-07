# Round 3: rendered preview and reopen lifecycle

AI review perspective inspired by John Ousterhout; this is not a review by John Ousterhout.

Reviewed PR #1 at `3502c7c`, against base `4c6cf45` and previous review heads `30791c5` and `4008592`. The Development app matches `3502c7c`. Production files were not edited.

## Finding O3 — P2: the script bridge retains rendered preview controllers

**Location:** `PreviewController.m:207-212`, especially `[windowScriptObject setValue:self forKey:@"Cocoa"]` at line 211.

Rendering a preview installs its controller as a JavaScript object. That object retains the controller, while the controller owns the WebView containing the script environment. The new release in `dealloc` balances the property only after controller deallocation starts; this cycle prevents it from starting for rendered previews.

**Trigger:** show a note preview, then close its browser. Repeating complete close-all/reopen cycles accumulates rendered preview controllers and WebViews.

The executable probe renders two different notes in separate previews, closes all browser windows, then reopens and closes the same shared library four times. It counts real nib connections and deallocation calls. Explicit autorelease-pool drains avoid retaining observed objects in the test.

```sh
python3 Tests/ReviewEvidence/round3/ousterhout/run.py
NV_PREVIEW_BRIDGE_CONTROL=1 python3 Tests/ReviewEvidence/round3/ousterhout/run.py
```

Production fails the lifetime assertion after an eight-second cleanup wait. The control suppresses only the script callback's single `setValue:self` assignment, retaining the same rendering and closure sequence. The control passes all 22 checks.

| Run | Additional browsers freed | Editors freed | Preview controllers freed | WebViews freed | Script callbacks |
| --- | ---: | ---: | ---: | ---: | ---: |
| Production | 5 | 5 | 0 | 0 | 11 |
| No controller bridge | 5 | 5 | 5 | 5 | 11 |

**Expected:** rendered preview resources are released after their browser closes. **Observed:** all five browser/editor pairs deallocate, while all five rendered preview controllers and WebViews remain allocated. Avoiding the controller bridge permits all five to deallocate.

**Repair:** keep the scripting API from retaining the window controller, for example through a separate logging object without a controller reference. Alternatively, provide explicit teardown that breaks the bridge before deallocation is required. Preserve `Cocoa.log` behavior if custom preview templates use it. Extend acceptance coverage to actually render previews; the previous eight-window fixture left them blank.

## Other evidence and limits

The production sequence successfully renders each owning note and repeats all four close-all/reopen cycles on the same library. The control also verifies that the retained initial service owner, preferences, and two shared notes remain usable after every browser closes.

An attempted preview-menu focus check did not make the utility panel the key window (`keyWasAlpha=0`). No command-routing defect is claimed from that observation.

The runner uses copied apps, random test preferences, temporary notes/support files, the shared GUI lock, and bounded process waits. It removes `DYLD_INSERT_LIBRARIES` from the environment after loading the harness so the external markup helper does not inherit it. No live sync, external editor, or preview sharing operation was exercised. The evidence counts retained objects; it does not estimate memory bytes or CPU cost.
