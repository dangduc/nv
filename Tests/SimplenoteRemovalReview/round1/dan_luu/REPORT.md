# Round 1: local storage operation counts

Dan Luu-inspired evidence and performance review. This is a review perspective, not participation or endorsement by Dan Luu.

Reviewed PR source: `f38a8cb3f1e5f74c57cfe5e8d5791f364201f1cb`, against `origin/master` at `9693356`.
The current app is frozen at `build/SimplenoteRemovalReview/round1.app`.
The baseline is `build/SyntaxFlickerReview/fix.app`, built before Simplenote removal at `65e1608`.
The five storage, preferences, note, and journal implementations under review have no changes between that baseline and `9693356`.

**No introduced defect found in this scope.** The paired experiment passed 83 native checks in each app.
Snapshot, journal, encoding, decoding, and retained-object counts matched in all eight cycles.

## Experiment

[checks.inc](checks.inc) and [prefix.h](prefix.h) run inside disposable copies of the real applications.
The baseline application generated 1,024 notes with 2,127,872 source characters, deterministic UUIDs, tags, and local syntax metadata.
Each note also contained synthetic remote metadata. The synthetic account was disabled and had no password.

The generator normalized the library through the actual baseline controller before saving the common input fixture.
Each app then opened, flushed, closed, and reopened that identical fixture for eight cycles.
Cycle four edited 64 notes. Each cycle also made five extra unchanged flush calls.
Every reopen checked all source characters, UUIDs, titles, tags, and syntax values.

Instrumentation wrapped the actual snapshot writer, WAL writer, note encoder, note decoder, and note destructor.
All wrappers called the original implementation. A pointer set tracked decoded notes without retaining them.
The probe mapped journals to separate temporary directories because the normal cache path is shared within one application instance.
No real notes, credentials, or network services were used.

## Results

| Measurement | Baseline | PR |
| --- | ---: | ---: |
| Completed close/reopen cycles | 8 | 8 |
| Successful snapshot writes | 8 | 8 |
| Successful WAL records for 64 edits | 64 | 64 |
| Extra snapshots from 40 unchanged flush calls | 0 | 0 |
| First stored snapshot, bytes | 2,133,727 | 1,667,790 |
| Edited snapshot, bytes | 2,136,534 | 1,669,074 |
| Notes encoded per cycle | 1,024 | 1,024 |
| Notes decoded per cycle | 2,048 | 2,048 |
| Final tracked live decoded notes | 16,384 | 16,384 |

The PR removed 465,937 bytes from the first snapshot of this synthetic library.
After migration, unchanged cycles retained identical archive bytes. The 64-note edit changed the bytes once, then subsequent snapshots remained identical.
The byte saving depends on this fixture's remote metadata; it is not an estimate for typical user libraries.

[compare.py](compare.py) asserts the paired counts and archive stability from the recorded logs.
See [comparison.log](comparison.log), [baseline.log](baseline.log), [current.log](current.log), and [generate.log](generate.log).

## Controls and limits

Two initial assumptions failed on the baseline and were corrected before the paired run:

- Reopening already writes one snapshot. `NotationController.m:1155` restores the foreground preference, and `NotationPrefs.m:296` marks it changed unconditionally.
  The PR adds no snapshot writes to this existing path. Five further flushes per cycle write nothing.
- Closing the controller does not release every decoded note within the probe's pool.
  The existing verifier retains `notesToVerify` at `NotationController.m:263` without releasing it.
  Deferred work can also retain controller notes in this synchronous probe. The experiment therefore compares live-object counts instead of asserting zero.
  Both apps retained the same 2,048 additional decoded notes per cycle. This does not establish total process memory use or explain every retained object.

The relevant original failures are preserved in [baseline-lifetime-assumption.log](baseline-lifetime-assumption.log) and [baseline-write-assumption.log](baseline-write-assumption.log).
These are existing behaviors, not findings against this PR.

The first generator omitted filenames. Opening several unattached notes then reached the baseline filename-collision loop.
The corrected fixture assigns distinct filenames, as stored notes normally have.
The initial cache-path trial also exposed the test's two-controller journal collision; the final prefix isolates those journals.
Their short logs are [generate-fixture-error.log](generate-fixture-error.log) and [generate-cache-isolation-error.log](generate-cache-isolation-error.log).

This experiment covers unencrypted single-database storage and disabled historical account metadata.
It does not cover encrypted archives, plain-file storage, user-visible startup latency, process RSS, or crash recovery.
The application's timing log lines were not used for performance claims.

The source changes at `NotationPrefs.m:143`, `NoteObject.m:543`, and `FrozenNotation.m:28` omit remote metadata during decode or the next snapshot.
The ordinary save path still clears dirty state at `NotationController.m:572` after the verified atomic write succeeds.
The measured stable snapshots and unchanged-flush checks agree with that contract.

## Reproduce

Run from the repository root with the frozen apps available:

```sh
mkdir -p build/SimplenoteRemovalReview/dan_luu
NV_DAN_DIRECTORY="$PWD/build/SimplenoteRemovalReview/dan_luu" NV_DAN_GENERATE=1 python3 Tests/ViewControlsReview/run-probe.py --probe Tests/SimplenoteRemovalReview/round1/dan_luu/checks.inc --prefix Tests/SimplenoteRemovalReview/round1/dan_luu/prefix.h --app build/SyntaxFlickerReview/fix.app --timeout 180 > Tests/SimplenoteRemovalReview/round1/dan_luu/generate.log 2>&1
NV_DAN_DIRECTORY="$PWD/build/SimplenoteRemovalReview/dan_luu" python3 Tests/ViewControlsReview/run-probe.py --probe Tests/SimplenoteRemovalReview/round1/dan_luu/checks.inc --prefix Tests/SimplenoteRemovalReview/round1/dan_luu/prefix.h --app build/SyntaxFlickerReview/fix.app --timeout 180 > Tests/SimplenoteRemovalReview/round1/dan_luu/baseline.log 2>&1
NV_DAN_DIRECTORY="$PWD/build/SimplenoteRemovalReview/dan_luu" python3 Tests/ViewControlsReview/run-probe.py --probe Tests/SimplenoteRemovalReview/round1/dan_luu/checks.inc --prefix Tests/SimplenoteRemovalReview/round1/dan_luu/prefix.h --app build/SimplenoteRemovalReview/round1.app --timeout 180 > Tests/SimplenoteRemovalReview/round1/dan_luu/current.log 2>&1
python3 Tests/SimplenoteRemovalReview/round1/dan_luu/compare.py
```

Recorded environment: macOS 26.5.2, Xcode 26.6, x86_64 application under Rosetta.
All three final native commands and the comparison command exited zero.

SHA-256 identifiers for this run:

```text
baseline binary: ee8e9ca27c99d55ff867afabd49e75c12f5548f49ac93dc733f514f477cac365
PR binary:       d61aea6619f6c4322efac164d7409ac131aa0ce2a8760d874850c34443331ede
input fixture:   9b9ff9856e1b205d247ad1363e8301b313b22f1bdfdc2dddd38ef2471c1981d9
```

The generated archive is a build artifact, not committed evidence. Regenerating it can change timestamps and compressed bytes.
No production or regression-suite files were edited for this review.
