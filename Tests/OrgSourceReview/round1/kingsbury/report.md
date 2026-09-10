# Org source review, round 1: state and concurrency

This review uses a Kyle Kingsbury-inspired perspective on observable state and concurrent work.
It does not represent Kyle Kingsbury.

No actionable defect emerged from the reviewed publication and lifecycle paths.
The native probe passed 52 checks with the production parser and highlighter.
The run used macOS 26.5.2 and Xcode 26.6, with Intel code under Rosetta and a macOS 10.13 deployment target.

## Evidence

Run this command from the repository root:

```sh
python3 Tests/OrgSourceReview/round1/kingsbury/run.py
```

The runner compiles the unchanged production `NVSourceHighlighter.m` and all bundled grammar wrappers.
A test subclass calls the real parser, then holds its completed result before delivery.
The highlighter keeps its production queue, cancellation token, generation checks, scheduling, capture application, and closure logic.
The result gate forces successful obsolete results to arrive after state changes.
It does not substitute fabricated captures or duplicate the publication algorithm.

The tests cover these interleavings:

- An initial Org result waits before publication. Both layouts remain uncolored until delivery.
- A completed DONE result waits while source edits and an Org → Plain Text → Org transition occur. The obsolete result cannot publish.
- Coalesced edits produce a replacement request with the latest immutable source. Only the final TODO result becomes current in both layouts.
- A layout moves to another note before new analysis. Its old capture token cannot display against the different storage identity.
- The last layout detaches while a successful Org result waits. The owner closes, and a new owner publishes JSON captures on the reused storage.
- The old Org result then arrives. It cannot replace the new captures, alter source attributes, or color the layout attached to another note.
- The closed owner deallocates after its callback. The reopened owner supplies its current captures to a reattached peer.
- The user selects Plain Text before the first Org delivery. Both the obsolete Org result and the later empty result leave source uncolored.

The probe also checks provisional colors, exact source preservation, and the absence of syntax attributes in shared text storage.
Each layout retains its independent search background on unchanged text.
TextKit can remove temporary attributes on replaced characters. That behavior is outside the search-background assertion.

The [output](output.txt) records all 52 checks.
The [metadata](metadata.json) records source hashes and the host toolchain.
The inputs remained unchanged during the successful build and run.
The run used commit `e7e1c9343e2d5394dc492151ed9c8d68c356feff` plus the concurrent scanner hardening changes identified by those hashes.

## Code assessment

`NVSourceHighlighter` advances its generation after source edits and syntax changes.
Its completion callback requires the current generation and syntax before it applies captures.
The generation comparison prevents a previous Org result from passing after a return to the same syntax.

`NVSourceCaptureRevision` also binds a revision to its storage identity.
The revision token prevents a reused layout from displaying captures from another note.
Closure invalidates tokens even after layouts detach, and queued blocks retain the owner until its callback completes.

`NVNoteEditingSession` closes the highlighter after its last layout detaches.
This probe exercises that sequence directly with the production highlighter.
It does not drive the session or browser controller through live windows.

## Limits

These are three deterministic schedules with bounded note fixtures.
They do not prove all scheduler interleavings, latency under load, complete Org conformance, or operation on macOS 10.13.
This review does not independently exercise disk archives, metadata migration, browser Undo, IME composition, or app relaunch.
The existing Org integration suite covers several of those paths separately.
No production files changed for this review.
