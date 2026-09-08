# Round 2: parser ownership and error handling

Perspective: Linus Torvalds-inspired review criteria, without impersonation.
Baseline: PR #4, commit `f037c7b781fa2a3c58d7b00cb440ba3e7239b615`.

No new actionable finding was confirmed in this bounded review.

## Evidence

The new probe compiles the production renderer into an isolated Intel executable.
It wraps the parser call to observe concurrent context, SAX handler, and status addresses.
The wrapper delegates every diagnostic to the production callback.
It does not change production files.

Command:

```sh
python3 Tests/SourceViewerReview/round2/linus/run-parser-isolation-probe.py
```

Observed output:

```text
Production: PASS: valid=56 limit=8 actual-later-diagnostics=0 peak-independent-contexts=8 ownership-failures=0 result-failures=0 accumulator-sequence-failures=0/4
Negative control: FAIL: valid=56 limit=8 actual-later-diagnostics=0 peak-independent-contexts=8 ownership-failures=0 result-failures=0 accumulator-sequence-failures=4/4
PASS: the last-diagnostic-only negative control fails the same assertions
PASS: renderer and preview availability checks compile for macOS 10.13
```

The 64 requests mix recovered HTML5 paragraphs, 9 MiB paragraphs, and 11 MiB paragraphs.
All successful documents retain their start, end, and trailing markers.
All eight oversized text nodes fail with `NVMarkupLimitExceeded` and no partial result.
Eight parser calls overlap. Each active call has separate context, SAX handler, and error-status storage.
Failures in one request do not affect valid requests.

This host emits no later diagnostics after these resource failures.
The probe therefore tests the accumulator separately with four explicit diagnostic sequences.
Each fatal or resource error is followed by a recoverable unknown-tag diagnostic.
The production callback retains every failure category.
The negative control clears accumulated state before each callback; all four sequence assertions then fail.
These sequences test the callback contract. They do not claim that this host's parser emits those sequences for the paragraph fixtures.

## Adjacent paths and limits

The parser context is freed after parsing. Both rejected and accepted documents have matching document cleanup paths.
The status pointer remains valid throughout the synchronous parser call.
No process-wide handler is installed by the renderer.

Inspection found matching helper pipe cleanup after success, failure, timeout, and cancellation.
The round 1 helper-lifetime probe already checks forced termination and callback ownership.
This round did not add a second executable helper-lifetime check.

The renderer and preview compile with an Intel macOS 10.13 target and unguarded-availability warnings treated as errors.
The newer WebKit find and print methods remain behind macOS 11 availability checks.
These compiler checks use the current SDK. They do not establish runtime compatibility on macOS 10.13.
No desktop app, user library, network service, or production file was changed by these probes.
