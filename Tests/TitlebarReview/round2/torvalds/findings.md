# Round 2: toolbar compatibility and restoration

No actionable production defect emerged from this focused review. Severity: none.

This review applies a correctness and compatibility perspective inspired by Linus Torvalds.
It does not represent his identity, review, or endorsement.

The production change is `6b8d67514f4fc5bc2e9fca22816a32f30f59fb1c` against upstream `89d9abe`.
The positive run started at head `2566d427ba3d7ace7e12b672bf6ab0fd5f08d845`.
The negative run started at `4cf0da05215d7da775d5c5c9191ba845702df28f` after another review commit.
The reviewed production sources match `6b8d675` in both runs.

## New executable evidence

Commands from the repository root:

```sh
python3 Tests/TitlebarReview/round2/torvalds/run.py
python3 Tests/TitlebarReview/round2/torvalds/run.py --negative
```

The actual copied Intel app passed **196 assertions** on macOS 26.5.2 (25F84) with Xcode 26.6 (17F113).
Both AppKit runs used authorized desktop access and the shared `build/pr-review/gui.lock`.
The common runner supplied a unique preferences domain and disposable notes.

The new probe requests twelve combinations:

- Window toolbar styles: Expanded and Unified Compact.
- Toolbar display modes: Icon Only, Icon and Label, and Label Only.
- Toolbar size modes: Regular and Small.

Every combination preserves the original enabled search item, container, and nib field.
The field frame equals the container bounds and retains its 24-point height and minimum editing width.
Search immediately focuses a visible native field editor.
The selected note and query remain unchanged.

The probe hides each toolbar while its search editor is active.
It then assigns the notes list as first responder and shows the toolbar.
Showing the toolbar does not steal that later responder.
A subsequent Search command focuses the field normally.
The semantic note title remains correct and visually hidden throughout the mode changes.

The delegate rejects empty, unknown, and obsolete item identifiers.
Three restored configurations contain no valid item: an empty list, an unknown action, and only the removed action icons.
Each configuration produces an empty toolbar.
Search restores exactly one item and reuses the original field and container.
Repeated Search commands do not duplicate the item.
All transitions preserve the source characters and the single fixture note.

## Negative control

The negative control replaces only `setDualFieldIsVisible:` inside the copied process.
Its replacement changes visibility but omits the missing-item insertion.
All twelve mode combinations still pass before this mutation takes effect.
Recovery from the empty configuration then fails at `Search recovers exactly one valid toolbar item`.

The copied app exits with status 1 after 166 successful assertions.
The review runner exits with status 0 because it requires that exact expected failure.
This control establishes that the probe detects a missing recovery step rather than merely exercising AppKit calls.
Production sources and the source app binary remain unchanged.

## Source and output records

Relevant production code is in `Sources/Browser/AppController_BrowserUI.m:335` and `Sources/Browser/AppController.m:2192`.

| Input | SHA-256 |
| --- | --- |
| `AppController_BrowserUI.m` | `6a179cb93dfe10052bb894b077cb969a1a748862646adbe35cec4b4cdcf1a33a` |
| Source app executable | `5b672807c892a9e12b8b1ce8291f17853bb93780cd4caf80946885198e47d8ca` |
| New `checks.inc` | `4ed339cdc7be76320fc0121048f0f022d5bdb0d1740da8a7820785501c052c20` |

Logs and JSON records reside in `build/TitlebarReview/round2/torvalds/`.
The records contain command arguments, exit status, assertion counts, and source hashes before and after each run.
Both records report no changed inputs and an unchanged source app executable.

## Limits

Expanded style on macOS 26.5.2 does not establish compatibility with the actual macOS 10.13 AppKit implementation.
The probe requests display and size modes through public APIs. AppKit can adapt their visible presentation.
The restored dictionaries exercise the native configuration API directly, not a user-accessible customization workflow or a relaunch.
The production toolbar disables customization and configuration autosave.

This probe adds no localization, fullscreen, live-resize timing, or source-editing coverage.
It does not repeat round-one menu routing and SDK availability checks.
It excludes the separate shared-body Undo exception reproduced on the unchanged baseline.
This review changed only its new code and report. It made no production edits or commits.
