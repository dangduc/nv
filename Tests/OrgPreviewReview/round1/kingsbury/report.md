# Org preview review, round 1: asynchronous state and closure

This review uses a Kyle Kingsbury-inspired perspective on observable state and recovery.
It does not represent Kyle Kingsbury.

No actionable defect emerged from these paths.
The new native probe passed **79 checks** against commit `4467e7a7251ff3846c6d255db3bd64f465fda6b2`.
Production input hashes remained unchanged during the build and run.

## Evidence

Run this command from the preview worktree:

```sh
python3 Tests/OrgPreviewReview/round1/kingsbury/run.py
```

The runner creates an isolated app bundle with the actual Org helper.
It compiles the production snapshot, renderer, and preview controller.
It uses a real `WKWebView` and temporary export destination.
The runner holds the common GUI lock during the probe.

A renderer subclass holds completed results before delivery to the provider.
The production renderer still runs the helper, transports its output, sanitizes HTML, and creates the immutable result.
The gate changes delivery order without fabricating HTML or copying the provider's publication logic.
The provider retains its production cancellation, generation checks, WebKit navigation, export, and closure paths.

Eight requests exercise four schedules:

1. A completed Org result waits while a different HTML note becomes visible.
   The obsolete Org result then arrives and cannot replace the current HTML or DOM.
   A caller mutation also leaves the Org snapshot and converter output unchanged.
2. Two Org requests for the same note deliver in reverse order.
   The older result cannot replace the current source generation.
3. An unsupported-viewer failure waits while a successful Org request becomes visible.
   The obsolete error cannot hide the current document or set its error state.
4. An HTML export response waits while another Org request completes and the original provider closes.
   A new provider then displays a different Org note.
   The export response writes exactly the original displayed bytes after closure.
   The old result subsequently arrives, releases the closed provider, and leaves the new provider unchanged.

The probe checks the actual DOM after current publication and after obsolete completion.
It also checks exact snapshot identity, viewer identifiers, exported bytes, closure state, and eventual provider deallocation.
The [output](output.txt) records all 79 checks.
The [metadata](metadata.json) records source hashes, the helper hash, and the toolchain.
The successful run used macOS 26.5.2 and Xcode 26.6, with Intel code under Rosetta.

## Code assessment

`displaySnapshot:viewerIdentifier:` captures the provider request generation in each completion.
`cancelRendering` advances that generation before a replacement request starts.
The completion guard rejects obsolete success and failure results before either can change presentation state.
Org uses these existing checks through the same renderer interface.

`close` marks the provider closed before it cancels work and clears the result.
The callback can retain the provider until delivery without permitting presentation after closure.
`saveHTML:` retains the displayed result independently of the provider's later selection and lifetime.
The export callback therefore uses the captured document and title.

## Limits

These are four deterministic schedules, not an exhaustive scheduler search.
Cancellation occurs after actual conversion completes, at the delayed delivery boundary.
The probe does not independently exercise cancellation during helper execution, timeout cleanup, shared editing sessions, IME composition, or window restoration.
The unsupported-viewer request supplies a production error for ordering checks, not a simulated helper failure.
The export panel is a test double. The renderer, exported document, file write, and WebKit view remain real.
The successful run needs an active desktop session. It does not establish operation on macOS 10.13.

An initial sandboxed launch aborted before the first probe check and produced no output.
The desktop-authorized run then completed all checks.
No production files changed for this review.
