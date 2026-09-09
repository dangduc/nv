# Round 1: Kingsbury perspective

Reviewed [PR #10](https://github.com/dangduc/nv/pull/10), application change `6b8d67514f4fc5bc2e9fca22816a32f30f59fb1c` against `89d9abe`.
The perspective is state transitions and consistency, without impersonating Kyle Kingsbury.

No actionable finding in the reviewed scope.

## Executable evidence

Run from the repository with desktop access:

```sh
python3 Tests/TitlebarReview/round1/kingsbury/run.py
```

The runner loads `checks.inc` into a copied Intel app. Each run uses disposable notes, support files, and preferences.
The shared runner holds `build/pr-review/gui.lock` throughout the AppKit process.

The ordinary run passed 354 checks across two launches: 326 before exit and 28 after restoration.
Four operation histories used two browsers with different queries, search modes, and selected notes.
Each history hid both toolbars, resized the windows independently between 480 and 1,200 points, and restored search focus.
It then typed through the field editor, renamed the selected note through its editing session, injected a legacy toolbar configuration, and closed and recreated the secondary browser.
The last process saved both histories. A new process restored their independent query, mode, selection, hidden title presentation, and full-width search.

The assertions compare application state with explicit expected values. They establish that:

- Showing one toolbar leaves its peer hidden.
- The common toolbar identifier does not share field or item instances.
- Query text remains distinct from the selected note's title.
- Both browsers retain one shared notes library and exactly two fixture notes.
- Search focus is immediate, and delayed work does not steal later body focus.
- Legacy configuration does not restore action icons.
- Closing and restoring a peer does not change the surviving browser's state.

The negative control replaces `selectSearchField` in the copied app with a wrapper that copies the window title into the search field.
Normal native focus still passes. The independent visible-query assertion then fails, as expected, after 10 passing checks.
The negative control exits 1; the overall review runner exits 0 only when it detects this exact failure.

## Recorded identity and results

The run used macOS 26.5.2 and Xcode 26.6, build 17F113.
The checkout reached `228eac2da61a71884df7da6fd860a1b113cc030c` while other review evidence was recorded.
The four production files below remained byte-identical to reviewed commit `6b8d675`.

| File | SHA-256 |
| --- | --- |
| `Sources/Browser/AppController.h` | `d222dcbaec7b680dbcbc46022b100c0e75c7d7b166110d87134be1e9e65acbb4` |
| `Sources/Browser/AppController.m` | `46a9c9f6f0aee838d547dd7b0ef17fa80f97978e1e951ffa0dca91229dac67be` |
| `Sources/Browser/AppController_BrowserUI.m` | `6a179cb93dfe10052bb894b077cb969a1a748862646adbe35cec4b4cdcf1a33a` |
| `Sources/Browser/AppController_MultipleWindows.m` | `9aebd2d5c24e99706a208dd35889c4ad1bcbb65c0e32739728ba7a94ec3b3145` |
| `checks.inc` | `d9b250541defbb38a95a0d80adfd6444c295c6e97e86d34b21f64a7ecf938628` |
| Built `nvALT` executable | `5b672807c892a9e12b8b1ce8291f17853bb93780cd4caf80946885198e47d8ca` |

Ignored artifacts are `build/TitlebarReview/round1/kingsbury/history.log`, `query-clobber.log`, and `results.json`.

## Limits

This is a bounded, deterministic history test on one macOS release. It does not prove correctness for every AppKit schedule or older macOS release.
It uses real AppKit controls and production methods, but does not synthesize physical keyboard or mouse events.
It does not cover full-screen transitions, input-method composition, or shared-body Undo.
The parent review separately established that the shared-body Undo failure also occurs on the unchanged base.
