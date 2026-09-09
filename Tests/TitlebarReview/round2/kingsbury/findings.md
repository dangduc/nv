# Round 2: Kingsbury perspective

No new actionable finding in the reviewed scope.
This review uses state histories and consistency checks inspired by Kyle Kingsbury. It makes no identity or endorsement claim.

Reviewed [PR #10](https://github.com/dangduc/nv/pull/10), production commit `6b8d67514f4fc5bc2e9fca22816a32f30f59fb1c` against `89d9abe`.
The starting review HEAD was `2566d427ba3d7ace7e12b672bf6ab0fd5f08d845`.
Other review records advanced HEAD to `4cf0da05215d7da775d5c5c9191ba845702df28f` during execution.
All nine recorded production files matched `6b8d675` and remained unchanged before and after both runs.

## New executable histories

Run from the repository root with desktop access:

```sh
python3 Tests/TitlebarReview/round2/kingsbury/run.py
```

The runner uses the actual copied Intel app, disposable notes and preferences, and `build/pr-review/gui.lock`.
The normal run passed **107 checks** across four new histories with two browsers and three notes.
The independent model declares visible query, committed query, mode, selected document, result currency, toolbar visibility, item presence, and search focus.
Expected values come from explicit history steps rather than observed application state.

1. A fuzzy Return waits for completion. The history hides the toolbar, removes Search, and restores native field focus.
   Toolbar detachment cancels Return and autocomplete. Completion keeps focus in Search, and later body focus survives delayed work.
2. A zero-result fuzzy Return waits while the toolbar hides. A newer Exact query selects another document.
   Search removal and restoration preserve that query, mode, and selection. The old fuzzy completion creates no note.
3. Reveal waits for a fuzzy result while its toolbar hides and the peer becomes active.
   Completion selects the requested document without showing the hidden toolbar or taking the peer's focus.
   A later Search command restores the original query, even though the selected document has a different title.
4. The native field editor receives marked text while an older fuzzy completion waits.
   The controller suspends search, rejects the old completion, and prevents Return from creating a note.
   Committing the text starts the new query. Toolbar hide, removal, and restoration preserve it through the current completion.

The production service still computes real search snapshots and native matching results.
A runtime wrapper holds only callback delivery on the main thread. Each history then chooses when to deliver a completed result.
The model checks distinguish pending and current results without relying on worker speed.

## Negative control

The separate control replaces `cancelTransientSearchIntents` with an empty implementation in the copied app.
It does so after the history records pending Return, immediately before native toolbar detachment.
The control fails after **27 passing checks** at:

```text
FAIL: native toolbar detachment cancels transient search intents
```

The negative process exits 1. The review runner exits 0 only when this exact failure occurs and the normal history succeeds.
Thus, a successful normal run does not result from a test that never checks cancellation.

## Identity and results

[results.json](results.json) records both commands, exit codes, counts, fixture hashes, and all nine source hashes before and after execution.
The built executable also remained unchanged:

```text
5b672807c892a9e12b8b1ce8291f17853bb93780cd4caf80946885198e47d8ca
```

The changed production files had these stable SHA-256 values:

| File | SHA-256 |
| --- | --- |
| `Sources/Browser/AppController.h` | `d222dcbaec7b680dbcbc46022b100c0e75c7d7b166110d87134be1e9e65acbb4` |
| `Sources/Browser/AppController.m` | `46a9c9f6f0aee838d547dd7b0ef17fa80f97978e1e951ffa0dca91229dac67be` |
| `Sources/Browser/AppController_BrowserUI.m` | `6a179cb93dfe10052bb894b077cb969a1a748862646adbe35cec4b4cdcf1a33a` |

Host: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), Intel application under Rosetta.
Ignored full logs are `build/TitlebarReview/round2/kingsbury/history.log` and `retained-transient.log` in the same directory.

## Limits

These are four bounded schedules on one macOS release. They do not establish correctness for all AppKit schedules or older releases.
The tests use real controls, field editors, browser controllers, sessions, service, library, and native matching.
They invoke native APIs instead of physical keyboard or mouse events.
Composition uses actual marked text plus an explicit field-change notification. It does not run an external input-method application.
The histories do not remove the toolbar while composition is still marked.
Programmatic item removal checks recovery even though this PR disables user toolbar customization.
This round does not repeat process restoration, full-screen tests, or the documented unchanged shared-body Undo failure.

This review changed no production code and created no commit.
