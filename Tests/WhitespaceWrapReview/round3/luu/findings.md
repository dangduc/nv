# Round 3: final short-note typing

This review uses a perspective inspired by Dan Luu. It does not represent his review or endorsement.

No new actionable finding emerged from the short-note typing comparison.
The final implementation eliminates glyph-buffer heap allocation in the measured small-batch typing sequence.

Reviewed head: `4b725372670afd5f5ecadf512deba8498336b2f0`.
Final binary SHA-256: `55f97d1af69d120f385698b428a616e473be020200d3fe0ebcc6b626253459be`.
Control binary SHA-256: `be02dd1fe33a39c74b8961441be55f4f91378d46935bdba99fd610d405c3e09b`.
The control has character wrapping and the shared paragraph style, before the buffer optimization.
Environment: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), Intel apps under Rosetta.

## Reported usage

Each actual copied app opens exactly 20 disposable notes with an empty search query.
The active note starts with `A short note with a few words. `.
Three trials run with Menlo 12, and three run with Helvetica 18.
Each trial sends 128 actual `NSApp` key events, with `isARepeat` after the first event.
The pattern alternates runs of 16 `k` characters and 48 spaces to cross wrapping boundaries.

The primary timing library installs no glyph observer or allocation interposition.
The probe checks the exact source, committed model, and logical caret after every event.
It also checks that the corpus still contains 20 notes and that the query stays empty.

| Median per 128 keys | Before optimization | Final |
| --- | ---: | ---: |
| Menlo event-dispatch total | 542.31 ms | 544.28 ms |
| Menlo main-thread CPU | 349.79 ms | 361.02 ms |
| Helvetica event-dispatch total | 538.55 ms | 550.34 ms |
| Helvetica main-thread CPU | 324.59 ms | 361.44 ms |

The median dispatch difference is approximately 0.4% for Menlo and 2.2% for Helvetica.
The CPU medians are greater in the final app, but the three-trial sample has substantial variance.
For example, control Helvetica CPU ranges from 280.55 to 374.91 ms; final Helvetica CPU ranges from 357.55 to 382.10 ms.
These samples do not establish a distinct typing regression or improvement.
They also do not prove equal CPU cost.

## Separate allocation sample

A separate library observes the real production glyph method and forwards every call unchanged.
Its allocation interposition counts `malloc` and `free` only while that method runs.
The sample uses 64 native key events with Menlo 12 in the same 20-note scenario.
Its timings do not contribute to the primary medians.

| Observed during 64 keys | Before optimization | Final |
| --- | ---: | ---: |
| Glyph callbacks | 128 | 128 |
| Changed batches of at most 64 glyphs | 112 | 112 |
| Changed batches larger than 64 glyphs | 0 | 0 |
| Scoped heap allocation calls | 112 | 0 |
| Scoped allocation bytes | 31,424 | 0 |

The largest observed batch contains 64 glyphs.
The final sample therefore exercises the local buffer through its upper boundary during actual typing.
Scoped free calls decrease from 208 to 96.
The remaining frees come from work inside the real method's callees; the scope does not count only the explicit buffer release.

## Reproduction and limits

Run `python3 Tests/WhitespaceWrapReview/round3/luu/run.py` for primary timings.
Run `python3 Tests/WhitespaceWrapReview/round3/luu/run.py --allocations` for the separate allocation sample.

The timing runs pass 1,552 checks per app. The allocation runs pass 134 checks per app.
Together they cover 1,664 actual key events across four copied-app runs.
All runs use the shared GUI lock, isolated preferences, temporary support paths, and disposable notes.

`timing-results.json` contains all primary trials.
`allocations-results.json` contains the scoped allocation sample and binary identities.
Counter fields in the timing file are zero because that run does not install instrumentation.
Logs, generated source, and build products remain under ignored `build/WhitespaceWrapReview/round3/luu`.
The recorded check count precedes the successful evidence-write check.

Main-thread CPU includes probe checks, logging, drawing, and deferred work between events.
This test samples key dispatch, rather than every displayed frame or physical held-key behavior.
It does not cover macOS 13, large-source typing, all fonts, or a second timing order.
