# Round 2: browser and preview lifetime review

AI review perspective inspired by John Ousterhout; this is not a review by John Ousterhout.

Reviewed PR #1 at `4008592`, using `4c6cf45...4008592` and the incremental `30791c5...4008592` changes. The copied Development app matches `4008592`. Production files were not edited.

## Finding O2 — P2: release the preview retained by each browser controller

**Location:** `PreviewController.m:745-754`, with the retained property declared at `PreviewController.h:51`.

Each browser eagerly loads its preview window. The nib connects the WebView through `setPreview:`, which retains it. `PreviewController` releases its other owned resources during teardown but does not release this property. Closing browser windows therefore leaves their WebViews allocated.

This was checked against real nib ownership, rather than inferred solely from the property declaration. The probe counts actual nib setter calls and deallocation calls without retaining the observed views. It opens and closes eight browsers, exercises substring access, and pumps the run loop long enough for editor teardown. A second run changes only the test interception of `PreviewController.dealloc`: it calls `setPreview:nil` before invoking the original method.

```sh
python3 Tests/ReviewEvidence/round2/ousterhout/run.py
NV_PREVIEW_OWNERSHIP_CONTROL=1 python3 Tests/ReviewEvidence/round2/ousterhout/run.py
```

Captured results:

| Run | Browser controllers freed | Editors freed | Preview controllers freed | Nib setter calls | WebViews freed |
| --- | ---: | ---: | ---: | ---: | ---: |
| Production | 8 | 8 | 8 | 8 | 0 |
| Release control | 8 | 8 | 8 | 8 | 8 |

**Expected:** releasing a closed browser's preview controller releases its owned WebView reference. **Observed:** zero of eight WebViews deallocate in production; balancing the property ownership permits all eight to deallocate during the same sequence.

**Repair:** release the retained preview reference during controller teardown, and preserve a real-nib lifetime check. Keep the change limited to ownership; the probe does not justify broader preview redesign.

## Round 1 fix verified

The production run exercises all eight delayed `LinkingEditor` deallocations after the O1 fix. Shared preferences remain usable at retain count one, and the shared note still contains `alpha beta gamma`. Both runs pass the runtime isolation checks and these four lifecycle checks. The earlier stalled editor teardown did not recur.

## Limits

The test uses a copied app with a random `org.nvalt.window-tests.*` preference domain, temporary notes and support storage, and the shared GUI lock. Runs require Rosetta execution outside the process sandbox. The runner has a timeout and does not wait indefinitely to reap a timed-out child.

No live sync, external editor, or preview sharing request was exercised. The probe establishes retained WebView instances; it does not estimate leaked bytes or CPU usage. No deleted-note cache defect is claimed.
