# Round 1: data-preservation skeptic

One actionable test-evidence gap was found and corrected in the permanent regression fixture.
No introduced production defect was found in this scope.
The review challenged whether obsolete remote fields could share or displace local source state during archive migration.
It did not require the removed remote service to keep working.

Reviewed commit: `f38a8cb3f1e5f74c57cfe5e8d5791f364201f1cb`.
Comparison base: `9693356`.
Environment: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), x86_64 app.

## Finding: P2 — generate recognized Simplenote account and remote metadata

Status: corrected after [the published PR comment](https://github.com/fastducduc/nv/pull/7#issuecomment-5591045833).
The finding and source line references below describe the reviewed `f38a8cb` version.

[The permanent generator, lines 12 and 15](../../../../Tests/Regression/source-storage/fixtures/generate.inc#L12), uses `Simplenote` as the service dictionary key.
The old app registers the service as `SN`; `Simplenote` is its display name.
The old preference lookup and note metadata lookup use that exact registered key.
The removed-note fixture also receives no remote metadata before becoming a tombstone at lines 16–20.

This means the permanent fixture does not exercise the recognized enabled account or pending remote records claimed by
[its README, line 16](../../../../Tests/Regression/source-storage/fixtures/README.md#L16), and
[the regression assertions, lines 7–9](../../../../Tests/Regression/source-storage/legacy-sync-compatibility.inc#L7).
Those assertions check only whether the outer archive keys exist.
They would pass even when the archive contains no recognized Simplenote state.
The fixture still tests preservation of local note data while ignoring an unknown service dictionary.

[recognition.inc](recognition.inc) passively inspects both fixtures with the actual old app.
It calls the old `serviceName`, `allServiceNames`, and `syncServiceIsEnabled:` methods, then reads the archived metadata.
It creates no sync session and makes no network or credential calls.
[recognition.log](recognition.log) records 10 passing checks and these results:

| Fixture | Registered SN enabled | Pending note metadata under SN | Tombstone metadata under SN |
| --- | --- | --- | --- |
| Permanent regression fixture | No | Absent | Absent |
| Independent old-native fixture | Yes | Present, dirty | Present |

Fix the generator to use the old class's `serviceName` for account, note, and tombstone metadata.
Assert recognition with the old app before writing the artifact.
Regenerate the fixed archive and update its documented hash.
This is a regression-evidence correction; the independent tests below found no corresponding production data-loss defect.
The initial review did not apply the fix; the delegated correction is recorded below.

## Delegated correction

The generator now obtains `SN` through the old `[SimplenoteSession serviceName]` method.
It supplies recognized dirty metadata for the live note and the deletion tombstone.
Before and after an archive self-read, the producer verifies the enabled account and both metadata dictionaries through old-app methods.
It does not start a service or read credentials.
[fixture-fix-producer.log](fixture-fix-producer.log) records **12 passing checks**.

The regenerated permanent fixture is 4,233 bytes.
Its SHA-256 is `07bc028440a8dfba96f53023f3035141a94c5b1ecd8b6cd23d99eaeb9bf52f4d`.
The fixture README records the new size, hash, and producer controls.

The permanent runtime test now verifies the exact account, live-note metadata, and tombstone metadata before migration.
Test-only archive records read those obsolete fields independently of the production decoder.
This adds no remote API to the application.
The full source-storage suite passed **273 checks**, including these preconditions and local library save/reopen.
[fixture-fix-source-storage.log](fixture-fix-source-storage.log) records the result.

[original-regression.notation](original-regression.notation) preserves the flawed fixture from `f38a8cb`.
Its SHA-256 remains `123f0b3dadb57501d031185d666c572fe54688c50cced21ea0a6966b39cf5105`.
The recognition command now reads this preserved artifact, so the original finding remains reproducible.
[recognition-initial.log](recognition-initial.log) retains the inspection before the permanent artifact changed.
[recognition.log](recognition.log) records the successful replay from the preserved copy.

[fixture-guard.inc](fixture-guard.inc) invokes the new permanent precondition helper against that original fixture.
It fails at the recognized-account assertion with exit status 1, as expected.
[fixture-fix-guard-negative.log](fixture-fix-guard-negative.log) records this sensitivity check.
Production code was unchanged.

## Code and evidence

[generate.inc](generate.inc) created a new fixture through the actual app from commit `65e1608ff4e9977ec2d7a09297739152f9cfc935`.
The four reviewed archive implementations are identical between that commit and `9693356`.
The review checked this with `git diff` for NoteObject, DeletedNoteObject, FrozenNotation, and NotationPrefs.
It did not reuse the source-storage regression fixture.

The fixture contains three local notes and one pending remote deletion.
Its account uses the actual old service identifier, `SN`, and a synthetic `.invalid` address.
Its upload metadata includes `key`, `dirty`, `modify`, `version`, and `SepStr`.
One note has the older metadata shape without `version`.
An ordinary unknown metadata flag and a disabled retired-service account are also present.

The local records include UTF-16LE with a BOM, CP1252, CRLF, tabs, Unicode, and unsent source characters.
They preserve fixed UUIDs, dates, tags, sequence numbers, and local syntax settings.
One record retains pending encoding conversion and a conflict-origin UUID.
Local syntax dictionaries also contain an unknown local property that must survive.

The old app read its own archive and matched all records against the source-state oracle.
[generate.log](generate.log) records 10 passing checks.
[expected.plist](expected.plist) contains that oracle.

[mutate.py](mutate.py) creates four variants containing ordinary but unexpected obsolete values: nil, a string, an empty array, and data.
Each variant changes exactly two outer obsolete fields and three note-level obsolete fields.
[mutate.log](mutate.log) records these counts.
The retained local fields are unchanged.

[checks.inc](checks.inc) reads each fixture with the reviewed app, then checks three successive rewrite reads.
All 20 archive reads preserve the complete local oracle.
Both unchanged source encodings export their exact original bytes on each read.
Every rewrite omits `syncServiceAccounts`, `deletedNoteSet`, and `syncServicesMD`.
[reader.log](reader.log) records **189 passing native checks** across five histories.

The result supports the boundaries at [FrozenNotation.m:26](../../../../Sources/Storage/FrozenNotation.m#L26),
[NotationPrefs.m:143](../../../../Sources/Preferences/NotationPrefs.m#L143), and
[NoteObject.m:531](../../../../Sources/Model/NoteObject.m#L531).
The keyed decoder skips remote fields while reading local note and syntax data independently.

The negative control changes only one local sequence number by one.
The same probe rejects that fixture at its source-state comparison, with exit status 1.
[negative.log](negative.log) records the expected failure.
No production code was changed to make the tests pass.

## Fixture correction and limits

The first producer comparison treated `NSStringEncoding` as a 64-bit numeric identity.
The old decoder sign-extends its archived 32-bit value.
[generate-initial.log](generate-initial.log) demonstrates this behavior in the old app.
The oracle now compares its low 32 bits, as documented in architecture.md.
Exact exported bytes are checked separately.
This is a corrected test assumption, not an introduced defect.

The fixture is unencrypted and keyed.
These tests cover archive decode/rewrite methods; they do not exercise journal recovery, complete library reopening, or crash interruption.
They do not preserve remote-only changes that never reached local storage.
They do not test unavailable classes, arbitrary archive corruption, real accounts, or credentials.
All app runs use the existing copied-app harness with disposable notes and isolated defaults.

## Reproduction

Run from the repository root:

```sh
NV_DATA_REVIEW_DIRECTORY="$PWD/Tests/SimplenoteRemovalReview/round1/contrarian_data" \
python3 Tests/ViewControlsReview/run-probe.py \
  --app build/SyntaxFlickerReview/fix.app \
  --prefix Tests/SimplenoteRemovalReview/round1/contrarian_data/prefix.h \
  --probe Tests/SimplenoteRemovalReview/round1/contrarian_data/generate.inc

python3 Tests/SimplenoteRemovalReview/round1/contrarian_data/mutate.py

NV_DATA_REVIEW_DIRECTORY="$PWD/Tests/SimplenoteRemovalReview/round1/contrarian_data" \
python3 Tests/ViewControlsReview/run-probe.py \
  --app build/SimplenoteRemovalReview/round1.app \
  --prefix Tests/SimplenoteRemovalReview/round1/contrarian_data/prefix.h \
  --probe Tests/SimplenoteRemovalReview/round1/contrarian_data/checks.inc
```

Add `NV_DATA_REVIEW_NEGATIVE=1` to the reader command to run the expected-failure control.
The passive service-recognition check uses this command:

```sh
NV_DATA_REVIEW_REPOSITORY="$PWD" \
python3 Tests/ViewControlsReview/run-probe.py \
  --app build/SyntaxFlickerReview/fix.app \
  --prefix Tests/SimplenoteRemovalReview/round1/contrarian_data/recognition-prefix.h \
  --probe Tests/SimplenoteRemovalReview/round1/contrarian_data/recognition.inc
```

Validate the correction with the permanent generator command in the fixture README, followed by:

```sh
python3 Tests/Regression/source-storage/run.py
```

Reproduce the expected failure against the original flawed fixture:

```sh
NV_DATA_REVIEW_FIXTURE="$PWD/Tests/SimplenoteRemovalReview/round1/contrarian_data/original-regression.notation" \
python3 Tests/ViewControlsReview/run-probe.py \
  --app build/SimplenoteRemovalReview/round1.app \
  --prefix Tests/SimplenoteRemovalReview/round1/contrarian_data/fixture-guard-prefix.h \
  --probe Tests/SimplenoteRemovalReview/round1/contrarian_data/fixture-guard.inc
```

Regeneration can change display-preference bytes in the archive.
The committed fixture hashes identify the reviewed artifacts:

| Artifact | SHA-256 |
| --- | --- |
| Old producer executable | `ee8e9ca27c99d55ff867afabd49e75c12f5548f49ac93dc733f514f477cac365` |
| Reviewed executable | `d61aea6619f6c4322efac164d7409ac131aa0ce2a8760d874850c34443331ede` |
| old-native.notation | `ab95fe38a571dc083ad3e2ef1c25f11a4a23758fcfaa8234ebf8ce8acd732a44` |
| expected.plist | `b15710c81bcff44c0b6ab612e264cb285e5365f3bc4c8d6a7b6845e159591bd1` |
