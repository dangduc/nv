# Round 1: Ousterhout-inspired review

Baseline: `5e44a909bd6b7b2ad1957c475f94594e0bffd461`.
Perspective: module boundaries, information hiding, and lifecycle ownership. This is an engineering perspective, not a review by John Ousterhout.

## Confirmed finding

**P2: An older viewer-state timeout can overwrite a newer capture.**

Locations: `Sources/Preview/PreviewController.m:237–250` and `Sources/Browser/AppController_Preview.m:66–76`.

Two captures can share the same library, note, and viewer identity. If the first WebKit query remains pending while a later query completes, the first capture's 0.5-second fallback subsequently writes its older cached scroll into `_displayState`. The browser also accepts that callback into `noteBodyStates`. The identity checks have no capture ordering. Reopening the viewer can therefore restore an older position even though a newer position was already captured.

The public capture contract permits a timeout and multiple outstanding calls. The provider should preserve each callback's call-time state while preventing stale callbacks from becoming the canonical restoration state. A monotonically increasing capture sequence, with an ordering check in each state consumer, would make that rule explicit. An alternative is to serialize captures and define their completion order.

Evidence:

```sh
python3 Tests/SourceViewerReview/round1/ousterhout/run.py
```

Result on macOS 26.5.2:

```text
Ordered replies control: provider scroll 200, browser callback state 200 (latest captured scroll 200)
New reply then old fallback: provider scroll 100, browser callback state 100 (latest captured scroll 200)
CONFIRMED: an older state capture overwrites a completed newer capture
```

The probe compiles the production `PreviewController`, snapshot, and renderer. A controlled web-view object holds the first DOM callback and completes the second. The real production timeout then delivers the first fallback. It does not modify the implementation. The browser-state consumer duplicates the current callback's unconditional dictionary replacement. This proves the ordering failure under delayed callbacks; it does not establish how frequently real WebKit produces that schedule.

## Rejected hypotheses

- Source-mode Save HTML might switch modes and silently lose the requested export. Menu validation disables that action outside Preview, so this is not a demonstrated user-facing regression.
- A queued render or capture callback might reopen a closed viewer. The close token, request generation, and `_closed` guards reject that path. Existing close/timeout tests cover it.
- A late capture from another library might enter the new library's state. The browser's presentation generation and library identity checks reject it.

## Boundary observation

The provider's immutable snapshots and explicit cancellation remove direct note/model dependencies. The remaining state-ordering defect comes from splitting one asynchronous restoration protocol between provider and browser without an ordering value. No broader abstraction rewrite is needed for this finding.
