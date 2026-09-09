# Round 3: invocation and lifetime contracts

This review uses a Linus Torvalds-inspired lens for low-level correctness and simple contracts.
It is an agent review, not a statement from that person.

Baseline: `8ebbcb511415958f700ca54e4216e6447464d284`.
The review read `AGENTS.md`, `architecture.md`, and `Tests/BackupReview/README.md`.
Host: macOS 26.5.2 (25F84), arm64, Xcode 26.6 (17F113).

## Findings

No new actionable finding in the reviewed scope. Severity: none.

The command guard initializes the complete return buffer before it rejects an invocation.
Its temporary buffer can leave scope before the caller reads the result.
The forwarding path restores the previous browser context after a nested exception.
Termination closes its temporary bypass after both normal completion and an exception.

| Production location | Evidence |
| --- | --- |
| `Sources/Application/NVApplicationController.m:503` | Rejected calls return complete zero values for ten return types. |
| `Sources/Application/NVApplicationController.m:512` | Application forwarding rejects the same calls without target execution. |
| `Sources/Application/NVApplicationController.m:365` | Resumed calls return their original values. Nested exceptions restore the outer browser context. |
| `Sources/Application/NVApplicationController.m:432` | The termination callback permits its checkpoint. Later calls remain blocked after both return paths. |
| `Sources/Browser/NVBrowserSession.m:230` | Real Objective-C messages use the production signature and forwarding methods. |

The review also traced replacement ownership and browser attachment at `Sources/Application/NVApplicationController.m:198` and `:259`.
Browser attachment uses direct library reads or local session queries for its main initialization data.
That inspection found no concrete regression from the active command guard.

## New executable evidence

`run.py` extracts the current production methods into `invocation-contract.m.in` without changes.
The fixture supplies recording browser, library, backup, and editing-session collaborators.
The compiler uses manual memory management and treats warnings as errors.
Each compile and process has a 30-second limit.

The probe covers these contracts:

- Ten return types: void, Boolean, integer, object, pointer, float, double, range, rectangle, and a 96-byte structure.
- Sixteen reject/resume cycles per type, including reuse of an invocation with an earlier nonzero result.
- Reads after the temporary autorelease pool drains, plus real message sends through the production browser-session forwarding path.
- A retained invocation that owns an object result, receives a rejected call, and releases its previous result exactly once.
- Nested invocation failure that preserves the outer browser context.
- Normal and exceptional termination callbacks that permit one checkpoint and then close the bypass.

Run from the repository root:

```sh
python3 Tests/BackupReview/round3/torvalds/run.py
NSZombieEnabled=YES python3 Tests/BackupReview/round3/torvalds/run.py
python3 Tests/BackupReview/round3/torvalds/run.py --regress-return
```

The default run passed all 668 assertions.
The run with Objective-C zombies also passed all 668 assertions and emitted no zombie diagnostic.
The mutation run removed return-buffer initialization in a temporary source copy.
The behavioral assertion rejected that mutation because a rejected call retained its earlier nonzero result.
The mutation runner returned success only after that expected rejection.

`git diff --check` passed for the review evidence.
The default runner uses current behavior and works with `Tests/BackupReview/run.py`.
The review changed no production code and created no commit.

## Limits

The probe runs native arm64 code. It does not establish the Intel application's ABI behavior.
The full Intel application stalls before `main` on this host, so the review did not start it.
The fixture does not exercise a real modal dialog, a full replacement initializer, or the complete browser attachment sequence.
It does not establish that every direct model callback passes through the forwarding guard.
The object-lifetime check covers invocation results, not all application resource ownership.
The probe opens no notes, external editors, or personal data.
