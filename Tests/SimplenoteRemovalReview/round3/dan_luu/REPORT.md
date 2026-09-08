# Round 3: deletion-history resource counts

Dan Luu-inspired evidence and performance review. This is a review perspective, not participation or endorsement by Dan Luu.

Reviewed production `f38a8cb` against PR base `9693356`. The fixture correction in `b418d84` does not change the app.
The current app is frozen at `build/SimplenoteRemovalReview/round1.app`.
The baseline is `build/SyntaxFlickerReview/fix.app`, built at `65e1608`; its relevant production files match `9693356`.

**No introduced defect found in this scope.** The PR passed 42 native assertions.
The baseline passed 43 assertions with passive remote metadata, and 43 more without it.
The extra baseline assertion confirms that no sync account is configured or enabled.

## Original experiment

[checks.inc](checks.inc) creates 96 notes in four batches of 24 inside a separate disposable database library.
Each note has 4,096 source characters, including Unicode, tabs, and CRLF. A separate UUID ledger identifies every note.

Each history creates a note, assigns tags, deletes it, performs Undo, then performs Redo.
Six notes per batch receive one final Undo and survive. Every history then clears the undo manager.
Each batch drains its autorelease pool and allows two 50 ms run-loop turns before counting original objects.
These intervals permit cleanup; they are not latency measurements.

The baseline's main run receives passive `SN` note metadata with a key, version, dirty flag, and modification timestamp.
It has no configured sync account. A separate baseline control omits all remote metadata.
No real notes, credentials, keychain items, or network services are used.

[prefix.h](prefix.h) wraps the actual note destructor, note and tombstone encoders, journal writer, and snapshot writer.
All wrappers call the original implementations. A set of pointer values tracks only the 96 explicitly created original notes; it does not retain them.
Snapshot encoder counts cover the explicit checkpoint call, outside the history's journal writes.
The library has no browser delegate or editing sessions. Its journal lives in a separate temporary directory.

## Results

Each application writes 78 note records and 48 deletion records per batch: **504 local journal records** across the whole workload.
The 78 note records comprise creation, tag persistence, Undo restoration, and the six final restorations.
All journal synchronizations and four verified checkpoints succeed in both applications.

| After batch | Surviving notes | Baseline live originals | PR live originals | Baseline snapshot tombstones | PR snapshot tombstones |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 6 | 24 | 6 | 18 | 0 |
| 2 | 12 | 48 | 12 | 36 | 0 |
| 3 | 18 | 72 | 18 | 54 | 0 |
| 4 | 24 | 96 | 24 | 72 | 0 |

Every checkpoint encodes each surviving note exactly once.
The PR releases all 72 deleted original notes after Undo is cleared. The baseline retains those originals through its remote deletion history.
With remote metadata absent, the baseline matches the PR's release and serialization counts in every batch.
This confirms that ordinary local deletion still uses journal tombstones while remote deletion history no longer accumulates in snapshots.

After each batch, the independent ledger verifies each removed UUID and the exact title, source, and tags of every survivor.
A real controller close and reopen preserves all 24 survivors and does not resurrect any of the 72 removed UUIDs.

See [current.log](current.log), [baseline.log](baseline.log), and [baseline-no-remote.log](baseline-no-remote.log).
[compare.py](compare.py) checks the three runs' batch counts and controls; its output is [comparison.log](comparison.log).

## Controls and fixture corrections

`NV_DAN_R3_RETAIN_DELETED=1` intentionally keeps deleted original notes in a probe-owned array.
The PR then fails its first lifetime assertion with 24 live originals instead of six.
[retention-control.log](retention-control.log) records the expected exit status 1. This tests the oracle, not an application fault.

The first fixture assigned nonempty tags in the note constructor.
Its expectation that all deleted originals would be released failed; adding more run-loop cleanup did not fix it.
Source inspection points to the constructor adding notes to label sets before assigning their UUID, which also determines their hash.
That constructor order predates this PR. The final fixture assigns tags through the public setter after creation.

The control `NV_DAN_R3_NO_REMOTE_METADATA=1 NV_DAN_R3_CONSTRUCTOR_TAGS=1` reproduces the lifetime failure in the baseline.
Its [log](baseline-constructor-tags-control.log) reports 10 live originals after the first batch instead of six.
The exact leftover count varied in initial trials; it is not a stable metric or a finding against this PR.
Those trials are recorded in [initial](lifetime-assumption-initial.log), [counted](lifetime-assumption-counted.log),
[one-turn](lifetime-assumption-oneturn.log), and [longer-cleanup](lifetime-assumption-tagged-constructor.log) logs.

An initial baseline metadata fixture omitted the modification timestamp required by its old update path.
[fixture-missing-modify.log](fixture-missing-modify.log) records that fixture error. The final metadata includes the timestamp.

## Limits

These are counts of explicitly tracked original model objects, not all live objects or process memory.
Decoded verification objects, browser editing-session caches, and general application lifetime behavior are outside this measurement.
The comparison does not establish RSS savings, UI latency, or a general performance bound.
It covers unencrypted database storage and a graceful reopen, not crash recovery, file-storage deletion, or enabled historical accounts.
The constructor issue is an existing behavior exposed by the initial fixture; this review requests no production fix for this PR.

## Reproduce

Run from the repository root with the frozen apps available:

```sh
python3 Tests/ViewControlsReview/run-probe.py --probe Tests/SimplenoteRemovalReview/round3/dan_luu/checks.inc --prefix Tests/SimplenoteRemovalReview/round3/dan_luu/prefix.h --app build/SimplenoteRemovalReview/round1.app --timeout 120 > Tests/SimplenoteRemovalReview/round3/dan_luu/current.log 2>&1
python3 Tests/ViewControlsReview/run-probe.py --probe Tests/SimplenoteRemovalReview/round3/dan_luu/checks.inc --prefix Tests/SimplenoteRemovalReview/round3/dan_luu/prefix.h --app build/SyntaxFlickerReview/fix.app --timeout 120 > Tests/SimplenoteRemovalReview/round3/dan_luu/baseline.log 2>&1
NV_DAN_R3_NO_REMOTE_METADATA=1 python3 Tests/ViewControlsReview/run-probe.py --probe Tests/SimplenoteRemovalReview/round3/dan_luu/checks.inc --prefix Tests/SimplenoteRemovalReview/round3/dan_luu/prefix.h --app build/SyntaxFlickerReview/fix.app --timeout 120 > Tests/SimplenoteRemovalReview/round3/dan_luu/baseline-no-remote.log 2>&1
NV_DAN_R3_RETAIN_DELETED=1 python3 Tests/ViewControlsReview/run-probe.py --probe Tests/SimplenoteRemovalReview/round3/dan_luu/checks.inc --prefix Tests/SimplenoteRemovalReview/round3/dan_luu/prefix.h --app build/SimplenoteRemovalReview/round1.app --timeout 120 > Tests/SimplenoteRemovalReview/round3/dan_luu/retention-control.log 2>&1
NV_DAN_R3_NO_REMOTE_METADATA=1 NV_DAN_R3_CONSTRUCTOR_TAGS=1 python3 Tests/ViewControlsReview/run-probe.py --probe Tests/SimplenoteRemovalReview/round3/dan_luu/checks.inc --prefix Tests/SimplenoteRemovalReview/round3/dan_luu/prefix.h --app build/SyntaxFlickerReview/fix.app --timeout 120 > Tests/SimplenoteRemovalReview/round3/dan_luu/baseline-constructor-tags-control.log 2>&1
python3 Tests/SimplenoteRemovalReview/round3/dan_luu/compare.py > Tests/SimplenoteRemovalReview/round3/dan_luu/comparison.log
```

The first three native commands and the comparison exit zero. Both controls exit one at the documented lifetime assertion.
Environment: macOS 26.5.2, Xcode 26.6, Intel application under Rosetta. The runner serializes native probes through the shared GUI lock.

```text
baseline binary SHA-256: ee8e9ca27c99d55ff867afabd49e75c12f5548f49ac93dc733f514f477cac365
current binary SHA-256:  d61aea6619f6c4322efac164d7409ac131aa0ce2a8760d874850c34443331ede
```

No production or permanent regression-suite files were edited for this review.
