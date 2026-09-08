# Round 2: state ownership and callback boundaries

This review uses a John Ousterhout-inspired perspective. It does not represent his views or participation.

No actionable regression was found at production commit `162c872`, compared with baseline `b27af28`.

The native probe passed 63 checks against the frozen PR app. The runner used a copied app, disposable notes, unique preferences, and `build/pr-review/gui.lock`.

This round extends the earlier metadata checks with these boundaries:

- All visibility callbacks preserve marked source text, its range, selection, focus, and deferred commit.
- Title hiding completes simultaneous native Title and Source compositions in separate windows that share one note.
- Native Undo removes the hidden Title edit before the earlier Source composition. Redo restores both edits in order.
- Each browser retains its own source responder after the shared metadata callback.
- The actual View menu changes syntax and Source/Preview mode for the active browser with hidden body controls.
- A completed preview callback preserves the active peer's menu state and focus.
- Same-note syntax notifications update the hidden peer control and preserve each browser's presentation mode.
- The commands preserve unrelated note content, metadata, and the number of notes.

The new layout callback uses the existing metadata commit boundary. The marked-input probe supports its ownership and Undo order.
The menu probe supports the distinction between application-wide visibility, per-note syntax, and per-browser presentation.

## Evidence

The environment used macOS 26.5.2, Xcode 26.6, and the Intel Development app under Rosetta.

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/ViewControlsReview/round2/ousterhout/checks.inc \
  --app build/ViewControlsReview/round1/nvALT.app
```

The command returned 0. `output.txt` ends with `OUSTERHOUT ROUND 2 PASSED: 63 checks`.

The mutation control redirected `selectSourceSyntax:` to the original browser after the peer became active:

```sh
NV_REVIEW_WRONG_SYNTAX_OWNER=1 python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/ViewControlsReview/round2/ousterhout/checks.inc \
  --app build/ViewControlsReview/round1/nvALT.app
```

The command returned 1. `mutation-output.txt` records the expected failure: `a peer menu command does not inherit the previous active note`.
The mutation existed only in the disposable process. It did not change production code or the app bundle.

## Limits

The probe used native `setMarkedText:` calls. It did not use a physical input method or test composition candidate windows.
The probe checked one completed preview render. It did not force every possible WebKit callback order or test live sync.
