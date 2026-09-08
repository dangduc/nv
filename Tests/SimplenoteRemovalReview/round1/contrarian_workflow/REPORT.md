# Round 1: contrarian workflow compatibility review

No actionable introduced defect found in the inspected local workflows.
The skeptical question was whether removing sync also breaks unrelated local navigation, preferences, toolbar restoration, or pending edits at quit.
Intentional removal of Simplenote account controls and sync URLs is outside this compatibility requirement.

Reviewed commit: `f38a8cb3f1e5f74c57cfe5e8d5791f364201f1cb`.
Comparison base: `9693356`.
Frozen app: `build/SimplenoteRemovalReview/round1.app`.
Executable SHA-256: `d61aea6619f6c4322efac164d7409ac131aa0ce2a8760d874850c34443331ede`.
Environment: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), x86_64 application.

## Independent executable evidence

[checks.inc](checks.inc) and [prefix.h](prefix.h) are original review code.
They use the copied-app runner for launch isolation, native controls, and temporary library paths.
They do not invoke an existing regression suite.
The runner locks GUI access and deletes its isolated notes and defaults afterward.

Run from the repository root:

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/SimplenoteRemovalReview/round1/contrarian_workflow/checks.inc \
  --prefix Tests/SimplenoteRemovalReview/round1/contrarian_workflow/prefix.h \
  --app build/SimplenoteRemovalReview/round1.app --launches 2 \
  > Tests/SimplenoteRemovalReview/round1/contrarian_workflow/native.log 2>&1
```

Exit status: **0**. [Full output](native.log).

```text
WORKFLOW ROUND1 phase1: 53 checks passed; invoking normal termination with unflushed pending input
WORKFLOW ROUND1 phase2: 6 checks passed
```

The 59 checks cover these independent histories:

- Six configurations restored with native `setConfigurationFromDictionary:`: Sync only, Sync plus New Note, New Note/Sync/Search, Sync plus flexible space, More/Preview, and an empty list. Removed IDs disappear. Search restores a hidden toolbar with exactly one usable field. Both windows retain their note and query.
- Two application Apple event routes use actual UUID note URLs with Unicode and punctuation in the titles. The active browser follows each link. The inactive browser retains its own selection and query.
- All four remaining Preferences panes open through their native toolbar actions. A search-highlight setting changes through its native action. Closing and reopening Preferences leaves both browsers alive. The setting persists after application relaunch.
- Two editors hold native compositions for different notes. The models still contain their pre-composition source before the quit decision. `applicationShouldTerminate:` commits both and returns `NSTerminateNow`.
- Both editors then start another composition. Normal `[NSApp terminate:]` runs with that pending input and without an explicit test flush. Relaunch finds exactly the two notes and verifies both complete source strings.

Relevant inspected code: `Sources/Browser/AppController_BrowserUI.m:351–365`, `Sources/Browser/AppController_Importing.m:70–95`, and `Sources/Application/NVApplicationController.m:329–338`.
The reduced toolbar factory lets Cocoa discard obsolete Sync IDs.
The local UUID route remains independent of the removed remote-ID route.
The coordinator retains its per-window editing completion before the termination reply and local persistence after that reply.

## Sensitivity check

An optional runtime mutation replaces only the copied app's `applicationShouldTerminate:` implementation with an immediate return.
It omits `finishEditing`, simulating accidental collateral removal beside the deleted sync wait.

```sh
NV_WORKFLOW_SKIP_FINISH_EDITING=1 python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/SimplenoteRemovalReview/round1/contrarian_workflow/checks.inc \
  --prefix Tests/SimplenoteRemovalReview/round1/contrarian_workflow/prefix.h \
  --app build/SimplenoteRemovalReview/round1.app --launches 2 \
  > Tests/SimplenoteRemovalReview/round1/contrarian_workflow/mutation.log 2>&1
```

Exit status: **1**, as expected. [Full output](mutation.log).

```text
PASS: two different note editors hold pending native compositions before termination
PASS: composition fixtures are still uncommitted in both note models
FAIL: termination completes all window compositions and returns immediately without remote wait
```

No production method or repository source was changed by this mutation.

## Fixture correction and limits

The [initial output](fixture-initial.log) stopped at opening Preferences.
The copied-app runner bypasses `applicationDidFinishLaunching:`, which constructs `PrefsWindowController` at `Sources/Browser/AppController.m:324`.
The first probe therefore sent the action to a nil controller.
The corrected fixture performs that same construction before testing Preferences. This was a fixture defect, not a product finding.

Toolbar histories exercise the native restoration API after launch, rather than importing old defaults before process startup.
Preferences tests verify pane transitions and one remaining setting; they do not cover every control or library-folder relocation.
The quit history uses two different notes and ordinary native marked text; it does not test failed disk writes, power loss, or every input method.
Measured decision duration is logged for context, not treated as a performance guarantee.
No real notes, credentials, keychain items, or remote services were used.
