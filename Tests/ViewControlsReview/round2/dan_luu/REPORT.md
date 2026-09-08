# Round 2: Dan Luu-inspired performance review

No actionable regression was established in this scope. This independent review uses a measurement perspective. It is not a review or endorsement by Dan Luu.

The probe ran against the frozen application for production commit `162c872`. All 409 checks passed. `output.txt` contains assertions, measurements, and JavaScript call stacks.

## Repeat the probe

Run from the repository root:

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/ViewControlsReview/round2/dan_luu/checks.inc \
  --prefix Tests/ViewControlsReview/round2/dan_luu/instrumentation.h \
  --app build/ViewControlsReview/round1/nvALT.app
```

The shared runner serializes desktop access and uses a copied application, temporary library, and isolated defaults.
The probe wraps production methods and calls each original method.

## Window lifecycle

The probe opened and closed one additional Source window 12 times. Both windows displayed the same note with Word Count visible.

Each new setting had exactly two observers with the additional window open. Each setting returned to one observer after that window closed.
No observer list contained a duplicate target. The shared text storage also returned from two source layouts to one after each closure.
All 12 additional browser controllers deallocated.

After each closure, six settings commands caused exactly six callbacks in the surviving browser, one word count, and four header layouts.
No command called a closed browser. No callback or source-layout accumulation appeared across these cycles.

## Live edits and resize

The source fixture started with 120,000 characters and 20,000 words. Each phase inserted `beta ` eight times through the native editor.
All windows displayed the correct count after each phase. Each edit left exactly one source layout per attached window before the event pool drained.

| Phase | Windows | Count calls for eight edits | Time inside word counting | Total synchronous insertion time | Individual insertion range |
| --- | ---: | ---: | ---: | ---: | ---: |
| Before window cycles | 1 | 16 | 228.6 ms | 430.1 ms | 52.8–56.1 ms |
| After window cycles | 1 | 16 | 234.0 ms | 443.4 ms | 53.2–65.9 ms |
| Four attached windows | 4 | 40 | 596.2 ms | 810.6 ms | 95.5–120.5 ms |

These phases caused no header layouts, settings callbacks, viewer display requests, or JavaScript calls.
The measured count calls match the existing edit path: one refresh per browser and one additional count in the originating editor.
This PR leaves both dispatch paths unchanged. The count method adds its own autorelease pool.

With all three header controls hidden, the probe resized one of four windows 12 times. Word Count remained visible inside the header.
The commands took 351.1 ms in total. They caused no word counts, settings callbacks, viewer display requests, or JavaScript calls.
The shared note retained exactly four source layouts.

## Visible viewer and mode changes

A real HTML viewer completed navigation before these checks. Four reflow groups each changed body-control visibility and notes-list visibility eight times.
Each group caused 32 settings callbacks and 16 header layouts across four windows. Each group caused zero word counts and zero display requests.

The groups recorded two, three, two, and two JavaScript calls. Every call stack identified the existing `captureDisplayState:` timer.
That timer reads scroll state every 0.2 seconds while the viewer is visible. `PreviewController.m` has no changes between the base and this PR.

Four Source/Preview cycles reused the same viewer and retained one source layout for its note.
Each cycle caused zero word counts and one display request on return to Preview. Source entry captured scroll state once.
The remaining JavaScript calls restored scroll state or came from the timer. All source characters remained exact after the complete probe.

## Limits and fixture correction

The initial run incorrectly required zero JavaScript calls with a visible viewer. `initial-output.txt` preserves that failure.
The final probe waits for WebKit navigation and records call stacks. Those stacks identify the timer, separate from the tested visibility commands.

Times cover synchronous native calls and instrumentation overhead. They exclude run-loop waits and do not measure completed painting or input-to-display latency.
The probe used macOS 26.5.2, Xcode 26.6, and an Intel Development application under Rosetta on an ARM64 host.
This bounded fixture covers 12 window cycles, 24 insertions, 12 resizes, and four mode cycles. It does not establish general latency or memory bounds.
There was no baseline timing run. The results do not establish a performance improvement or slowdown relative to the base.
