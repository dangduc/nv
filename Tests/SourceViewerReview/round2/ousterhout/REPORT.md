# Round 2: Ousterhout-inspired review

Baseline: `f037c7b781fa2a3c58d7b00cb440ba3e7239b615`.
Perspective: state ownership, asynchronous contracts, and browser/provider boundaries. This is an engineering perspective, not a review by John Ousterhout.

## Confirmed finding

**P2: A capture made during a repeated return discards the pending exact scroll.**

Locations: `Sources/Preview/PreviewController.m:224–231` and `Sources/Browser/AppController_Preview.m:61–73`.

Start with note A rendered at scroll 420 while its cached position is 100. Switch A → B → A, holding A's exact WebKit capture. The first return correctly preserves the pending capture. Switch away again before that capture finishes, either to B or to Source. A is still loading, with an empty display-state dictionary. The new capture advances the provider revision and replaces the browser request token, then completes immediately with that empty cache. The earlier exact reply of 420 can no longer update either consumer. Returning to A restores scroll zero.

The ordering fix handles two completed document reads, but treats a loading fallback as newer authoritative evidence. The provider and browser need to preserve the pending exact result across further captures of that still-loading presentation. Coalescing those requests is one possible fix. Explicit restoration must still invalidate earlier captures.

Evidence command:

```sh
python3 Tests/SourceViewerReview/round2/ousterhout/run.py
```

Result on macOS 26.5.2, using the clean built app at the baseline commit:

```text
Scenario 0 (A-B-A control): browser canonical 420, returned DOM 420, expected 420
Scenario 1 (A-B-A-B-A): browser canonical 0, returned DOM 0, expected 420
Scenario 2 (A-B-A-Source-A): browser canonical 0, returned DOM 0, expected 420
CONFIRMED: loading-state captures supersede outstanding exact state after repeated returns. Checks: 21
```

The probe runs the actual copied application, browser actions, provider, and DOM. Only WebKit capture delivery is held. It invalidates the cache timer to keep the schedule deterministic. All notes and preferences are disposable. The source uses ordinary Markdown; no production methods are replaced except the WebKit callback boundary. The probe asserts the reviewed failure and will need updating after its fix.

PR review: https://github.com/fastducduc/nv/pull/4#pullrequestreview-5139960168

## Separate regression-fixture diagnosis

The new round-one `source-workflow` assertion for A → B → A fails for a different reason. It creates the intermediate note inside the controlled transition. `MakeNote` calls `addNewNote:`, which reveals the new note with `NVEditNoteToReveal`. That action switches the browser to Source. Later calls with `options:0` do not return it to Preview. The assertion therefore inspects a provider that no longer represents the selected note.

Evidence command, expected to exit 1 at the existing assertion:

```sh
python3 Tests/SourceViewerReview/round2/ousterhout/diagnose-workflow.py
```

Output:

```text
DIAG before MakeNote viewing=1 loading=0
DIAG after MakeNote viewing=0 loading=0
DIAG after A viewing=0 loading=0
FAIL: rapid browser A to B to A retains A's pending capture instead of superseding it with cached restoration
```

Create both fixture notes before entering Preview. The new review probe does this, and its single-return control passes. This fixture issue does not disprove the separate repeated-return failure.

## Rejected concern and limits

- Closing the provider completes a pending capture once and clears its rendered result. Creating a replacement provider and allowing callbacks to run does not revive the closed provider.
- The normal A → B → A control restores the exact scroll. The first-round fix is effective for that schedule.
- Existing tests cover explicit saved-window restoration and older callback rejection. This round adds repeated transitions and closure through the real browser; it does not measure how often WebKit delays callbacks in ordinary use.
- No production files were changed during this review.
