# Round 3: ownership and complexity

Perspective: John Ousterhout-inspired review of module boundaries and state ownership. This is not a review by John Ousterhout.

Baseline: `9720676ccd0e619dba99f6a47d257216c1e383eb` (PR 4).

## Confirmed finding

**P2: Preserve each joined caller's current Find state.**

Location: `Sources/Preview/PreviewController.m:246`, within `captureViewerStateWithCompletion:`.

A loading capture correctly shares an earlier DOM read and its deadline. However, joining replaces the caller's entire cached state with the first caller's state. This also replaces a newer Find query, although only the scroll coordinates need to come from that earlier document.

The actual browser consumer makes this visible:

1. A loaded note uses Find query `Paragraph`. Window-state serialization starts an exact capture.
2. A native Find action changes the query to `newer`.
3. A refresh of the same note starts rendering. This uses the production refresh method called after a peer edit.
4. The user selects another note while that refresh is loading. The browser's departure capture joins the first read.
5. The exact read finishes, and the user returns to the original note.

The browser saves `Paragraph`, and the native Find field restores `Paragraph`. The provider had correctly retained `newer` before departure. Its joined callback supplies the older query, which the browser accepts as its latest request.

Share the pending scroll result, fallback offsets, and deadline. Keep each caller's own non-scroll state. Checking only the provider's current dictionary misses this defect because the browser also consumes the callback result.

## Executable evidence

`run.py` compiles the production snapshot, renderer, and provider sources. It substitutes the asynchronous renderer, WebKit reply boundary, and native fields. Production display, capture, completion, restoration, Find, and closure methods remain in use.

```sh
python3 Tests/SourceViewerReview/round3/ousterhout/run.py
```

At the reviewed baseline, it passes 40 checks, then returns 2 to identify the reproduced defect:

```text
Joined capture: query at call = newer query; callback query = original; provider query = newer query
OBSERVED: joined caller loses its own current Find state. 40 checks passed.
```

`run-browser.py` copies the built app, uses a unique preferences domain and temporary notes, and takes `build/pr-review/gui.lock`. It delays only delivery of the exact WebKit capture callback. It calls the real `browserWindowState`, Find action, `updateViewerSnapshot`, and note-selection paths.

```sh
python3 Tests/SourceViewerReview/round3/ousterhout/run-browser.py
```

The copied-app probe passes 11 checks, then returns 2 on the same baseline:

```text
Actual browser: latest query newer; saved query Paragraph; restored field Paragraph; preview scroll 420; source scroll 280
CONFIRMED: browser consumer loses newer Find state after capture, same-note refresh, departure, and return. Checks: 11
```

Local log: `build/round3-ousterhout-browser.log`.

## Tested rejections

The new provider histories use four joined callers with snapshot generations 1, 3, 5, and 7.

- Each caller receives its own snapshot generation and identity.
- Explicit restoration from the first completion survives later joined completions.
- Closing from the first completion still completes the other callers once and leaves the provider closed.
- A nested capture from the first completion sees the current snapshot and state without repeating old delivery.
- A repeated late WebKit reply cannot invoke any joined callback again.
- A matching note identifier in a different library cannot join the previous library's read or receive its canonical offsets.
- The copied-app failing history preserves Source scroll 280 and Preview scroll 420. Its failure concerns the Find query.

## Limits

The callback order is controlled; these probes do not measure its frequency in normal use. The copied-app run uses macOS 26.5.2 and Xcode 26.6. The source fixture uses the current production files; the copied app uses the reviewed build. No macOS 10.13 runtime was tested. No production file was changed during this review.
