# Round 1: low-level correctness and ownership

Perspective: Linus Torvalds-inspired review criteria, without impersonation.
Baseline: PR #4, commit `5e44a909bd6b7b2ad1957c475f94594e0bffd461`.

## Confirmed finding

**P2 — Reject parser limit failures instead of exporting truncated HTML.**

Location: `Sources/Preview/NVMarkupRenderer.m:31–34`.

The renderer accepts source up to 16 MiB. Libxml's default text-node limit is smaller.
`htmlReadMemory` returns a recovered document after truncation, and the renderer treats that document as success.
A valid paragraph with 11 MiB of text loses its final marker. No error reaches the caller.
Both Preview and Save HTML use this incomplete result.

Command:

```sh
python3 Tests/SourceViewerReview/round1/linus/run-boundary-probe.py
```

Observed output:

```text
9437184 input=9437217 output=9438152 start=1 end=1 error=none
11534336 input=11534369 output=10000943 start=1 end=0 error=none
15728640 input=15728673 output=10000943 start=1 end=0 error=none
```

The probe compiles the production renderer and uses ordinary paragraph text with two markers.
The 9 MiB case is a control. The 11 and 15 MiB cases remain below the declared source limit.
Handle parser resource-limit errors explicitly and return a structured failure. Do not export a recovered partial document as success.
Keep recovery for ordinary malformed HTML when it preserves content. Add a regression for this boundary.

## Disproved concern

The cancellation path does stop a helper that ignores SIGTERM. It also reaps the process after renderer release.
The probe starts a disposable converter, cancels its operation, releases the renderer, and checks callback count and process existence.

```sh
python3 Tests/SourceViewerReview/round1/linus/run-helper-lifetime-probe.py
```

Observed output:

```text
PASS: SIGTERM-ignoring helper PID 36648 stopped/reaped in 0.223s; exactly 1 main-thread cancellation callback after renderer release
```

The probe uses a temporary bundle and cleans up its helper in a `finally` block.
No production files changed. Desktop UI was not required.

## Other inspected paths

Reviewed manual ownership in render completion, state capture, cancellation, and provider closure.
The completion block transfers to the main queue before the operation releases it.
Provider closure clears timer and delegate references. The state-capture owner token prevents callbacks from using a closed provider.
No additional actionable defect was confirmed in these paths.
