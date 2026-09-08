# Round 1: Ousterhout-inspired design review

No actionable introduced defect was found in this scope. This review uses an Ousterhout-inspired design perspective. It does not represent John Ousterhout or his endorsement.

Reviewed production revision: `65e1608` against base `8cd2c9591041b8cdef367c6a0f78304e00192a45`.

## Contract and ownership

The change separates two states which previously shared one validity check: colors that can still appear, and captures that describe the current source.
`NVSourceCapturesAreCurrent` requires both states. The editor's display callback uses only `NVSourceCapturesCanDisplay`.
This keeps the provisional display policy inside the highlighter. Callers do not need to manage delayed attribute removal.

The storage identity remains borrowed. Its safety depends on the highlighter retaining storage and retiring the revision before that ownership ends.
Closure invalidates the shared revision object, including associations retained by detached layout managers. A later attachment cannot revive that retired revision.
The character notification releases absolute capture ranges. A newly attached layout therefore waits for analysis instead of copying obsolete ranges.

These checks cover the changes in `NVSourceHighlighter.m` at lines 19–25, 255–265, and 296–300, and the existing close path they use.
No production edit was needed.

## Executable evidence

[probe.m](probe.m) compiles the actual highlighter and pinned parsers against Cocoa. It does not launch the application or read user notes.

```sh
python3 Tests/SyntaxFlickerReview/run-parser-probe.py --probe Tests/SyntaxFlickerReview/round1/ousterhout/probe.m
```

Result: **200 checks passed**, exit 0. [Recorded output](output.txt).

Twelve histories each verify:

- Two layouts share current captures, then keep shifted display captures after an insertion while current semantics become false.
- A third layout receives no obsolete captures and does not clear peer colors.
- Moving a layout to another storage rejects its previous revision.
- Switching to Plain Text clears captures and preserves an independent background attribute.
- Returning a detached layout to its original storage cannot revive a retired revision.
- A fresh JSON parse reaches all three layouts.
- Closing after the last layout detaches retires associations held outside the highlighter.
- A new highlighter can replace a retired association. Source characters stay exact, and source storage receives no capture attribute.

The final history holds one parser request with semaphores, then closes and releases its highlighter.
It releases the external storage reference before permitting a successful obsolete result to return.
The retained asynchronous work keeps the owner alive until completion. Then both the highlighter and its parser deallocate, and no retired revision becomes valid again.

## Negative control

```sh
python3 Tests/SyntaxFlickerReview/round1/ousterhout/run-negative-control.py
```

[run-negative-control.py](run-negative-control.py) writes a temporary implementation under `build/`.
It changes display permission to require current semantics, recreating the contract error that causes the flash.
The native probe fails check 4, `pending source keeps display permission`, with exit 1.
The wrapper verifies that exact failure and exits 0. [Recorded output](mutation-output.txt).

## Limits

These checks use native text storage and layout managers with JSON fixtures. They do not measure rendered pixels, typing latency, physical input methods, or full browser-window lifecycle.
The held result is synthetic; the initial result uses the real JSON parser. This isolates close and completion ownership from parser cancellation.
The tests establish the observed object lifetimes. They are not a general leak detector or an exhaustive scheduler exploration.
