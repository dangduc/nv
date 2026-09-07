# Round 3: Metadata history capacity and ownership

This AI review uses a John Ousterhout-inspired perspective on abstraction and ownership. It does not represent his participation or views.

Reviewed HEAD: `0afeb03837b94c1a16da211a79c9eaf8dfe51183`.
Production revision and supplied app: `12936fed78e1d98ac646bb88b51e009609ad505e`.
Comparison baseline: `116daff`.
Environment: macOS 13.7.8, Xcode 15.2.

## Result

No actionable finding in two bounded cases. The independent probe passed 2,851 assertions across 217 initial edits and two complete undo/redo cycles.

The history limit retained exactly 200 actions. One pending title commit on browser closure evicted one older action. Redo restored the retained actions in order.

## Scope

- `NVNoteEditingSession.m:126-131`: the 200-action limit and metadata target allocation.
- `NVNoteEditingSession.m:223-258`: undo/redo and metadata action registration.
- `NVNoteEditingSession.m:294-298`: body action registration.
- `AppController_BrowserUI.m:160-181`: the pending native header edit and its commit.
- `AppController.m:1760-1767`: browser closure.

The probe covers history eviction and repeated use of one metadata target. It does not repeat Round 2's library replacement or deallocation cases.

## Command and fixture

```sh
python3 Tests/NativeUIReview/round3/ousterhout/run.py
```

The runner acquires `build/pr-review/gui.lock`. It compiles an injection library and copies the supplied Development app into a temporary directory.

The copied app gets a unique bundle identifier and defaults domain. Both notes and application support use temporary directories.

The harness suppresses normal launch actions, external editor initialization, and `startSyncServices`. Launch Services starts the app with `open -W -n` and explicit injection environment values.

The app launch has a 90-second timeout. The runner removes the unique defaults domain after the app exits.

Native activation assertions require the actual key window and main window. Each history action also requires the original browser's actual body responder.

The assertions dispatch `undo:` and `redo:` through `NSApp`. They do not change the coordinator's active-browser state directly.

## Case 1: Mixed edits exceed the history limit

The probe makes 217 independent edits. Actions repeat in this order: title, tags, body.

Metadata edits use the production coordinator API. Body edits use the native body editor. Each action receives a distinct value derived from its sequence number.

An independent oracle calculates the expected title, tags, and body from that number. It checks every forward, undo, and redo transition.

The probe also checks that every forward edit uses the same session and metadata target. This observation covers target identity, not retained memory size.

| Measurement | Expected | Actual |
| --- | --- | --- |
| Initial edits | 217 | 217 |
| Available undo actions | 200 | 200 |
| State after all available undo actions | Action 17 | Action 17 |
| Available redo actions | 200 | 200 |
| State after all available redo actions | Action 217 | Action 217 |

At the retained floor, the values were `Title016`, `tag017`, and `Body015`. The final values were `Title217`, `tag215`, and `Body216`.

## Case 2: Browser closure commits a pending title at capacity

The second case starts with the restored, full history from Case 1. A peer browser opens the same note and starts native title editing.

The probe enters a distinct title and checks that the model still contains `Title217`. It then closes the peer browser with the edit pending.

Closure commits the pending title. The original browser then dispatches all available undo and redo actions through its native body responder.

| Measurement | Expected | Actual |
| --- | --- | --- |
| Title immediately after closure | The pending title | The pending title |
| Metadata target | The original target | The original target |
| Available undo actions | 200 | 200 |
| State after all available undo actions | Action 18 | Action 18 |
| Available redo actions | 200 | 200 |
| Final title | The title committed on closure | The title committed on closure |

The final tags and body remained `tag215` and `Body216`. Neither history direction exposed an extra action after its expected endpoint.

## Actual output

Selected lines from `run.log`:

```text
R3 CAP firstUndoCount=200 floorAction=17 expectedCount=200 expectedFloor=17
R3 CAP firstRedoCount=200 finalAction=217
R3 CAP closeUndoCount=200 floorAction=18 expectedCount=200 expectedFloor=18
R3 CAP closeRedoCount=200 finalTitle=Title committed on close at capacity
OUSTERHOUT ROUND3 PASSED (2851 checks)
```

## Baseline distinction and limits

The original baseline already sets the 200-action limit. It lacks the native header and separate metadata undo target.

This probe ran against the supplied corrected app only. It makes no runtime baseline equivalence claim and reports no new regression.

The assertions establish a bound on exposed history actions. They do not establish a bound on retained bytes, cached sessions, or long-running application memory.

The probe uses generated edits in one temporary note. It does not cover large note bodies, physical keyboard events, live sync, or external editors.

The run emitted the existing AppKit layout-recursion warning. These cases do not establish its cause or user impact.
