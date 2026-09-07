# Round 1: lifecycle and information-hiding review

AI review perspective inspired by John Ousterhout; this is not a review by John Ousterhout.

Reviewed `4c6cf45...30791c5` for PR https://github.com/dangduc/nv/pull/1. Production files were not edited.

## Finding O1 — P1: do not release borrowed preferences when a browser editor closes

**Location:** `LinkingEditor.m:1768`, reached by the new browser teardown at `AppController.m:2158` and `NVApplicationController.m:147`.

`LinkingEditor` assigns `prefsController = [GlobalPrefs defaultPrefs]` in `awakeFromNib` (`LinkingEditor.m:80`). That accessor returns the process singleton without retaining it (`GlobalPrefs.m:186-191`). The editor later sends it `release` in `dealloc`. The new multiple-window lifecycle releases additional browser controllers while the application continues to use that singleton.

**Expected:** closing an additional window leaves the shared preferences object alive.

**Observed evidence:** the source-matched ownership probe compiles the exact accessor, assignment, and release statements extracted from these production files. Releasing the simulated editor destroys the singleton, while the accessor retains its stale pointer. Removing only the borrowed release in the probe prevents its destruction.

```sh
python3 Tests/ReviewEvidence/round1/ousterhout/ownership-probe.py
```

Output in `ownership.log`:

```text
current:
before editor closes: singleton retain count=1
after editor closes: singleton deallocated=YES; accessor still returns same pointer=YES
negative-control:
before editor closes: singleton retain count=1
after editor closes: singleton deallocated=NO; accessor still returns same pointer=YES
```

The real Cocoa probe separately confirms reachability: eight opened and closed additional windows yield eight `AppController` deallocations. A `LinkingEditor` then reaches its production `dealloc` during subsequent run-loop work. The application's observed singleton retain count remains one until that point. This is logged in `results.log` and `singleton.log`.

**Repair:** make the editor's preferences ownership consistent. Audit adjacent `controlField` and `notesTableView` releases as borrowed nib outlets, and exercise delayed editor destruction after closing windows. Do not retain the singleton merely to conceal unbalanced releases.

## Scope and limits

The GUI evidence uses a copied application, a random `org.nvalt.window-tests.*` bundle identifier, temporary notes, and temporary support storage. Runtime checks confirm that isolation. It serializes through `build/pr-review/gui.lock`.

Both GUI runs stopped progressing after the `dealloc linkinged` message; Rosetta children entered `UE` process state. This is a diagnostic observation, not proof of the crash location. The second run's preferences-deallocation interceptor was not reached. The wrappers were stopped to release the GUI lock, and the runner now avoids waiting indefinitely to reap a timed-out child.

The suspected retention of deleted notes by `editingSessions` was not reached in these GUI runs and is **not** reported as a confirmed defect. Eight controller deallocations also rule out the initial hypothesis that browser controllers themselves remain retained after every close. The executable source-matched probe supplies the causal evidence for O1; no claim is made that it models all AppKit teardown behavior.
