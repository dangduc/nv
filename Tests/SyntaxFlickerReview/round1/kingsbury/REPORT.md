# Round 1: Kyle Kingsbury-inspired state review

This review uses a concurrency and state-history perspective inspired by Kyle Kingsbury. He did not participate or endorse it.

Reviewed production commit `65e1608` against base `8cd2c9591041b8cdef367c6a0f78304e00192a45`.

**No actionable introduced defect found.** Retained display colors do not bypass the existing generation fence in the tested histories.

## Executed evidence

`probe.m` compiled the production highlighter and pinned Tree-sitter grammars as a native Intel executable. It passed **161 assertions across ten gated worker histories**. See `output.txt`.

The parser subclass uses semaphores to hold a captured request until the main thread changes state. Its synthetic results deliberately ignore cancellation. This tests publication checks independently of parser cancellation.

| History | Observed result |
| --- | --- |
| Character edit while positive, nil, or empty result waits | All three obsolete results preserve provisional colors in both layouts. Current semantic permission stays false. A fresh real parse restores it. |
| Syntax changes JSON → HTML → JSON while JSON result waits | The first syntax change clears colors. Matching syntax text does not let the obsolete result publish. |
| Layout moves to another note while first note's result waits | The second note's real colors survive the obsolete completion, a fresh first-note parse, and closure of the first highlighter. |
| Close with positive, nil, or empty result waiting | Closure clears colors immediately. None of the three late results restores them. |
| Current nil or empty fallback follows an edit | Both current fallback outcomes clear provisional colors. Real parsing then recovers. |

The histories also check immutable source snapshots, generation increments, exact final source text, and unchanged independent-note text.

The relevant production paths are `NVSourceHighlighter.m:255` (edit invalidation), `:268` (syntax changes), `:313` (publication fence), and `:322` (closure).

## Negative control

`run-negative-control.py` removes only `generation == requestGeneration` from a temporary implementation copy. The first stale-positive history fails assertion 8. See `mutation-output.txt`.

The failure is expected. It establishes that the probe detects publication of a canceled generation even when syntax still matches. No production source is changed.

## Reproduction

From the repository root:

```sh
python3 Tests/SyntaxFlickerReview/run-parser-probe.py \
  --probe Tests/SyntaxFlickerReview/round1/kingsbury/probe.m
python3 Tests/SyntaxFlickerReview/round1/kingsbury/run-negative-control.py
```

## Limits

These checks exercise native TextKit storage, temporary attributes, queues, and main-thread completion. They do not draw the application UI or measure flicker perception.

Semaphores select ten explicit histories. They do not exhaust every possible ordering. Parser cancellation itself, physical IME input, display-operation limits, crash durability, and end-to-end typing latency are outside this probe's scope.

The fixture cancels debounce timers between transitions and invokes analysis directly. It tests completion safety, not debounce timing or automatic scheduling liveness.
