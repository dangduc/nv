# Round 2: plain-file persistence counts

Dan Luu-inspired evidence and performance review. This is a review perspective, not participation or endorsement by Dan Luu.

Reviewed production `f38a8cb`, against PR base `9693356`. The current app is frozen at `build/SimplenoteRemovalReview/round1.app`.
The baseline is `build/SyntaxFlickerReview/fix.app`, built at `65e1608`.
The relevant note, editing-session, preferences, file, controller, and journal implementations have no changes between that baseline and `9693356`.

**No introduced defect found in this scope.** Both apps passed the same 78 native checks. Local write counts and exact source bytes matched.

## Original experiment

[checks.inc](checks.inc) creates eight notes in a separate plain-file library inside each disposable application copy.
The source includes UTF-8 non-ASCII text, an emoji, CRLF, and LF characters. Both apps receive the same generated source and operations.

The workload makes 660 source commits through `NVNoteEditingSession`: 320 insertions, 320 deletions, and 20 paced insertions.
It also makes 96 selection changes, 96 tag changes, and 96 syntax changes.
These operations are newly written review code. They do not invoke an existing regression suite.

[prefix.h](prefix.h) wraps successful atomic file replacements and successful WAL record writes. Every wrapper calls the original implementation.
Counters include only the measured library and its journal. The source-file counter excludes the library snapshot.
The probe reads the journal bytes after synchronization and counts complete record headers and payloads. Those physical counts must match the writer counts.
It independently checks exact UTF-8 source bytes on disk after each source or metadata phase.

The journal directory is isolated per library. This avoids the two-controller cache collision found in Round 1.
Directory notifications are stopped for the measured library to isolate its scheduler and explicit persistence operations.
No real notes, accounts, credentials, or network services are used.

## Paired results

Each row shows the result from **both** implementations. Counts cover successful operations after fixture setup.

| Phase | Source-file replacements | WAL records | Snapshots |
| --- | ---: | ---: | ---: |
| 320 insertion commits, then explicit flush | 8 | 8 | 1 |
| Five unchanged flushes | 0 | 0 | 0 |
| 320 deletion commits, then explicit flush | 8 | 8 | 1 |
| Five unchanged flushes | 0 | 0 | 0 |
| 96 selection changes, then explicit flush | 0 | 8 | 1 |
| 96 tag changes, then explicit flush | 8 | 8 | 1 |
| 96 syntax changes, then delayed preference save | 0 | 0 | 1 |
| 20 paced source commits, then idle save | 1 | 1 | 0 |
| Explicit snapshot flush after idle save | 0 | 0 | 1 |
| Five final unchanged flushes | 0 | 0 | 0 |
| **Total** | **25** | **33** | **6** |

The two large source bursts made zero synchronous file, journal, or snapshot writes. Each flush wrote each changed note once.
Selection metadata preserved source bytes and modification dates. Tag changes rewrote source files with identical bytes in both implementations.
Syntax changes saved only library preferences. Their delayed save produced one snapshot, with no note or journal writes.

The paced source edits each had a 10 ms run-loop interval. No file or journal write occurred during that burst.
A subsequent three-second run-loop interval allowed the existing idle scheduler to save one note and one journal record.
These intervals exercise batching; they are not latency measurements.

Every physical journal count matched its successful writer count. The 15 unchanged flushes wrote nothing.
A real controller close and reopen preserved all eight notes, exact source bytes, tags, syntax identifiers, and selection metadata.
The final checks inspect both reopened models and their actual source files.

See [baseline.log](baseline.log), [current.log](current.log), and [comparison.log](comparison.log).
[compare.py](compare.py) asserts all paired phase counts and totals.

## Sensitivity and limits

The control `NV_DAN_R2_FORCE_UNBATCHED=1` forces the real scheduler to drain writes after each dirty-note request.
The current app then fails the expected “320 source commits queue without synchronous persistence” assertion.
[unbatched-control.log](unbatched-control.log) records the expected exit status 1. This is a probe mutation, not an application defect.

The first compilation used an unsupported `dateModified` selector in the probe.
[fixture-compile-error.log](fixture-compile-error.log) records that fixture error. The final code uses the existing `modifiedDateOfNote` accessor.

This review covers a modest unencrypted plain-file workload, explicit flushes, the idle delay, and a graceful controller reopen.
It does not cover the 15-second continued-edit timer, external directory reconciliation, encoding conversion failures, crash recovery, or enabled historical accounts.
Journal framing counts do not independently verify journal cryptography or recovery. Source bytes and reopened state have separate assertions.
No wall-clock performance, process memory, or general write-amplification claim follows from this experiment.
No production change is requested from this round.

## Reproduce

Run from the repository root with the frozen apps available:

```sh
python3 Tests/ViewControlsReview/run-probe.py --probe Tests/SimplenoteRemovalReview/round2/dan_luu/checks.inc --prefix Tests/SimplenoteRemovalReview/round2/dan_luu/prefix.h --app build/SyntaxFlickerReview/fix.app --timeout 120 > Tests/SimplenoteRemovalReview/round2/dan_luu/baseline.log 2>&1
python3 Tests/ViewControlsReview/run-probe.py --probe Tests/SimplenoteRemovalReview/round2/dan_luu/checks.inc --prefix Tests/SimplenoteRemovalReview/round2/dan_luu/prefix.h --app build/SimplenoteRemovalReview/round1.app --timeout 120 > Tests/SimplenoteRemovalReview/round2/dan_luu/current.log 2>&1
NV_DAN_R2_FORCE_UNBATCHED=1 python3 Tests/ViewControlsReview/run-probe.py --probe Tests/SimplenoteRemovalReview/round2/dan_luu/checks.inc --prefix Tests/SimplenoteRemovalReview/round2/dan_luu/prefix.h --app build/SimplenoteRemovalReview/round1.app --timeout 120 > Tests/SimplenoteRemovalReview/round2/dan_luu/unbatched-control.log 2>&1
python3 Tests/SimplenoteRemovalReview/round2/dan_luu/compare.py
```

The first two native commands and the comparison command exited zero. The deliberate mutation command exited one.
Recorded environment: macOS 26.5.2, Xcode 26.6, Intel application under Rosetta. The runner serializes native app runs through the shared GUI lock.

Binary SHA-256 identifiers:

```text
baseline: ee8e9ca27c99d55ff867afabd49e75c12f5548f49ac93dc733f514f477cac365
current:  d61aea6619f6c4322efac164d7409ac131aa0ce2a8760d874850c34443331ede
```

No production or permanent regression-suite files were edited for this review.
