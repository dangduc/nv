# Round 2: Kyle Kingsbury-inspired scheduling review

This review uses a concurrency and state-history perspective inspired by Kyle Kingsbury. He did not participate or endorse it.

Reviewed production commit `65e1608` against base `8cd2c9591041b8cdef367c6a0f78304e00192a45`. The checkout at `6e6f04e` adds review evidence only.

**No actionable introduced defect found.** Automatic analysis converges after the tested edit, attachment, syntax, and closure histories.

## Executed evidence

The native Intel probe passed **155 assertions across six automatic scheduling histories**. See `probe.m` and `output.txt`.

Round 1 canceled debounce timers and started analysis directly. This round closes that scheduling gap: production timers start every analysis request.

The observer subclass counts timer entry and publication. It calls the production implementation unchanged. The test never invokes analysis directly or cancels a debounce request.

The parser uses semaphores to hold selected requests. Held requests return a synthetic capture and ignore cancellation. All other requests use production Tree-sitter parsing.

| History | Observed result |
| --- | --- |
| Twelve native timer-driven character edits | Both layouts retain JSON key colors after every edit. Semantic permission becomes false synchronously. After typing stops, both layouts become current. There were two parser calls, including initialization. |
| Debounce consumed while older work waits | A real timer enters analysis while the worker is busy. Three subsequent edits leave its retained source argument unchanged. Releasing the worker triggers automatic replacement analysis. |
| New layout joins during pending work | Existing peer colors remain visible. The new layout initially has no display permission. It receives the final real JSON captures with its peers. This shares the previous history. |
| Completion near a pending debounce | An edit schedules a timer, then the old worker is released immediately. One further timer attempt was observed. The final result becomes current without test intervention. |
| JSON changes to HTML during work | All three layouts lose old display permission immediately. An HTML debounce fires while JSON work waits. After release, all three receive current HTML tag captures at generation 22. |
| Last layout detaches before its timer fires | The timer runs without starting parser work. Reattaching a layout automatically restores current HTML captures. |
| Last detach and close while work waits | A moved layout receives another note's current JSON captures. The closed owner's late completion causes no publication or change to those captures. Closing the new owner removes its colors. |

The new-attachment checks share the consumed-debounce history, so the table describes six scheduling histories in seven rows.

Every eventual wait has a three-second deadline. These are failure bounds, not measured latency or performance guarantees.

The first gated history retains the actual production source argument. It compares that argument after three edits, without copying inside the parser fixture.

Final requests must match the exact source text, syntax, and generation. Publication instrumentation rejects the synthetic obsolete capture in every history.

The final two note sources remain exactly `<b>new</b>\n  ` and `{"peer":false}\n`.

## Negative control

`run-negative-control.py` removes only the stale-completion reschedule branch from a temporary implementation copy. Production files remain unchanged.

The mutant passes bounded typing, then fails assertion 96 in the consumed-debounce history. Current captures never arrive within the three-second bound. See `mutation-output.txt`.

This failure shows that the probe detects lost scheduling after an older request consumes the pending timer.

## Reproduction

From the repository root:

```sh
python3 Tests/SyntaxFlickerReview/run-parser-probe.py \
  --probe Tests/SyntaxFlickerReview/round2/kingsbury/probe.m
python3 Tests/SyntaxFlickerReview/round2/kingsbury/run-negative-control.py
```

## Limits

These checks use native TextKit storage, temporary attributes, the main run loop, dispatch queues, production debounce timers, and pinned Tree-sitter grammars.

They do not draw the app, simulate physical keyboard or IME events, or measure visible flicker. Bounded typing uses a twelve-event timer fixture.

Semaphores establish selected worker orderings. The completion-near-debounce history permits either timer/completion order and records the observed attempt count. It does not assert a precise race ordering.

The probe explicitly calls owner lifecycle APIs after layout changes. It does not verify the application's note-owner wiring or window closure callbacks.

It does not prove starvation freedom under unbounded typing, sustained main-thread blockage, or every possible interleaving. Parser cancellation behavior and crash durability remain outside scope.
