# Round 1: Kyle Kingsbury-inspired review

This is an independent review perspective, not a claim of authorship by Kyle Kingsbury.

Reviewed PR 14 application commit `504f303` against `b289ba3`.
No actionable findings.

The changed command captures the key browser's live field-editor string before it cancels search intents or ends editing.
It passes that captured value through the existing note creation and storage path.
The explicit title does not reuse another browser's query or the result of an obsolete search.

## Executable evidence

`prefix.h` gates actual successful `NVSearchService` worker completions immediately before their browser callbacks.
`probe.inc` runs this bounded schedule in a copied Intel app and a disposable shared library:

1. Open two browser windows. Each starts a fuzzy search whose real completion is held.
2. Queue Return while each browser's results remain pending.
3. Change the focused field editor without publishing that text as a query.
4. Dispatch Command-N through the native application menu in each browser.
5. Switch focus and deliver both obsolete results in reverse order, twice.
6. Check both note objects, UUIDs, titles, query states, selection, source focus, and total note count.
7. Checkpoint both notes, launch the copied app again, and compare persisted titles and UUIDs.

Result: **45 checks passed**, comprising 38 first-launch checks and 7 second-launch checks.
These counts include four temporary-library setup assertions.
Both creations retained their captured titles and distinct UUIDs.
Late callbacks created no additional note and did not change either browser's selected note.

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/FocusedSearchNewNoteReview/round1/kingsbury/probe.inc \
  --prefix Tests/FocusedSearchNewNoteReview/round1/kingsbury/prefix.h \
  --launches 2
```

The runner uses `build/pr-review/gui.lock` to serialize desktop probes.
Full output is in `output.txt`.
The tested app executable SHA-256 is `ffd2506757bfb23cfc26450ce1a736a578babd22af606a313427a6db7e399c43`.

## Limits

This is one deterministic two-window schedule, not an exhaustive concurrency model or a latency benchmark.
Forced duplicate delivery exceeds the service's normal callback contract and checks the browser's stale-result guard.
The persistence check covers a successful explicit checkpoint and reopen; it does not simulate storage failure or power loss.
The second launch logged journal startup diagnostics, then loaded the two notes with their exact recorded identities.
No conclusion about the existing broad-suite Undo or desktop-focus failures follows from this focused probe.
