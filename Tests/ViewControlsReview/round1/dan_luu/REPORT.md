# Round 1: Dan Luu-inspired performance review

This review uses a measurement-focused perspective. It is not a review or endorsement by Dan Luu.

No actionable regression was established in the measured paths.

## Evidence

The probe ran against frozen PR head `162c872`. It used the real application, disposable notes, and the shared desktop-test lock.
All 58 checks passed. `output.txt` contains the measurements and assertions.

Run from the repository root:

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/ViewControlsReview/round1/dan_luu/checks.inc \
  --prefix Tests/ViewControlsReview/round1/dan_luu/instrumentation.h \
  --app build/ViewControlsReview/round1/nvALT.app
```

Use `--app` with another Development app to repeat the probe after a rebuild.

A 120,000-character note contained 20,000 words. All browser windows displayed the same shared note.
The probe intercepted the production count, header layout, preview display, and WebKit script methods. Each wrapper called the original method.

| Windows | Count calls per Show Word Count command | Total synchronous command time, two runs | Time for 60 header commands |
| --- | --- | --- | --- |
| 1 | 1 | 16.7 ms, 15.8 ms | 32.2 ms |
| 2 | 2 | 31.1 ms, 29.4 ms | 39.3 ms |
| 4 | 4 | 59.6 ms, 61.3 ms | 49.8 ms |

The single-browser control used the same production count method with four attached source layouts. It took 15.7 ms and counted once.
Thus, the global Word Count action repeats the count for each browser. The measurement establishes linear repeated work on this fixture.
It does not establish a latency defect that warrants a separate PR finding.

Each header command called `layoutNoteHeader` once per browser. Across these commands, the probe observed:

- No word-count calls, preview display requests, or WebKit script calls.
- No preview-provider allocation in windows that had only shown Source.
- Four source layouts after word counting, with no retained temporary substring observers.
- Exact source character preservation.

A separate control loaded HTML in a real WKWebView. The counters observed one display request and one script call while loading.
After returning to Source, four hide/show cycles for the title and notes list caused zero display requests and zero script calls.
The probe pumped the run loop during these cycles and for 400 ms afterward.

## Scope and limitations

Times cover the synchronous action and nested layout calls. They do not measure completed painting, frame presentation, or user-perceived latency.
The test covers one note size and up to four windows. It does not establish bounds for larger notes or more windows.
All measurements ran on the current desktop through the Intel Development app under Rosetta.

The initial viewer fixture used the default Markdown helper. The injected test library propagated to that subprocess and caused a harness failure.
The shared runner now removes `DYLD_INSERT_LIBRARIES` after app injection. The completed idle-viewer fixture selects HTML explicitly.
That fixture failure is not a production finding.
