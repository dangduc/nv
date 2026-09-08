# Round 3: data-preservation skeptic

No actionable defect found in the corrected fixture or the reviewed migration paths.
The fixture correction addresses the round-one finding.
Six independent metadata controls fail the exact final fixture guard at the expected precondition.
The original fixture passes all three guard checks.

This is an independent skeptical review, not participation or endorsement by a named reviewer.

## Reviewed state

- PR head: `f9cc501628b1c4e61b7e655e205f0c36ca00260f`.
- Production implementation: `f38a8cb3f1e5f74c57cfe5e8d5791f364201f1cb`.
- Fixture correction: `b418d8466d2936de0fb62c8556ce3e0de4b9f106`.
- [Original finding and requested correction](https://github.com/fastducduc/nv/pull/7#issuecomment-5591045833).
- Tested executable: `build/SimplenoteRemovalReview/round1.app/Contents/MacOS/nvALT`.
- Executable SHA-256: `d61aea6619f6c4322efac164d7409ac131aa0ce2a8760d874850c34443331ede`.
- Fixed fixture SHA-256: `07bc028440a8dfba96f53023f3035141a94c5b1ecd8b6cd23d99eaeb9bf52f4d`.

The original fixed artifact is 4,233 bytes. The test does not replace it with a current encoder's output.
The known old producer and its hash remain recorded in the [fixture README](../../../Regression/source-storage/fixtures/README.md).

## Source review

The [generator](../../../Regression/source-storage/fixtures/generate.inc) obtains the service identifier through the old `SimplenoteSession` class.
It checks both the `SN` value and registration in `SyncSessionController.allServiceNames`.
The old source at the PR base defines `SimplenoteServiceName` as `SN`.
The account, live note, and tombstone use that returned identifier.
The generator checks account enablement and exact pending metadata before encoding and after passive decoding.
It never calls service startup or password methods.

The [permanent guard](../../../Regression/source-storage/support.h) reads the account and tombstone from the outer archive.
It reads live-note metadata from the compressed inner archive.
The three equality checks require the exact enabled account, dirty upload record, and dirty deletion record.
The guard runs before the [migration check](../../../Regression/source-storage/legacy-sync-compatibility.inc) opens the fixture in a local library.

The migration check uses fixed expected source, UUID, dates, sequence, title, tags, syntax, and source bytes.
These expectations are independent of the current encoder.
Its final rewritten-library assertion checks note count and source text; the separate probe here checks all listed local values after rewriting.

The production decoder changes omit obsolete keyed values while preserving local fields.
`NotationPrefs` marks an archive with the old account key for rewriting.
`FrozenNotation` retains preferences and packed live notes and drops remote deletion history.
`NoteObject` drops remote metadata while retaining source, identity, dates, and sequence fields.
The local journal tombstone remains a separate record; the fixed fixture's remote deletion history must not create a live note.

## Original executable evidence

[run.py](run.py) independently reads the fixed binary plist and its compressed note archive.
It verifies the three metadata dictionaries, local identity/content/syntax values, and the absence of encryption or a keychain identifier.
It creates ordinary typed-plist variants by changing the named field only.
It regenerates the archive compression wrapper and records each artifact hash in [manifest.json](manifest.json).
Generated variants live under `build/SimplenoteRemovalReview/round3-contrarian-data` and can be recreated from the committed fixture.

The script extracts the exact guard source from `support.h` into [fixture_guard.h](fixture_guard.h).
The extracted source SHA-256 is `19016e1cd329d0afae638a751ce0306eb66d4ab9ba27fd6548ed28d36998fa3b`.
[prefix.h](prefix.h) rebinds only the guard's assertion reporter to record all three results instead of exiting at the first failure.
The native [probe](checks.inc) requires the complete expected result vector for each variant.
It also runs each archive through the actual current `FrozenNotation`, `NotationPrefs`, and `NoteObject` decoders and encoder.

| Archive variant | Account guard | Upload guard | Deletion guard | Local oracle |
| --- | --- | --- | --- | --- |
| Original corrected fixture | Accept | Accept | Accept | Accept |
| Account service key changed from `SN` to `Simplenote` | Reject | Accept | Accept | Accept |
| Account disabled | Reject | Accept | Accept | Accept |
| Live-note metadata field removed | Accept | Reject | Accept | Accept |
| Live-note `dirty` changed to false | Accept | Reject | Accept | Accept |
| Tombstone metadata field removed | Accept | Accept | Reject | Accept |
| Tombstone remote key changed | Accept | Accept | Reject | Accept |
| Retained live-note sequence incremented by one | Accept | Accept | Accept | Reject |

The last control separates fixture preconditions from local preservation.
Its unchanged remote values pass the metadata guard, while the local oracle rejects the changed sequence both before and after rewriting.
Metadata-only variants preserve the local note across both reads.
The local oracle checks exact UUID, Unicode characters, CRLF, tab, title, tags, dates, sequence, UTF-8 bytes, and Markdown syntax metadata.
Every rewrite omits obsolete account, deletion-history, and note-metadata fields.

Result: **100 native assertions passed**, including two disposable-library setup assertions.
The probe observed **24 guard outcomes across eight variants** and **16 local archive reads**: original plus rewritten for each variant.
All six metadata controls rejected only the expected precondition.
The local sequence control rejected the preservation oracle on both reads.
Full output is in [run.log](run.log).

## Reproduce

From the repository root, with the preserved current app available:

```sh
python3 Tests/SimplenoteRemovalReview/round3/contrarian_data/run.py
```

The command uses the shared GUI lock, copied app, disposable notes directory, and isolated preferences domain from `run-probe.py`.
It does not launch the old app, enable a network service, or access real credentials or user notes.
This review ran on macOS 26.5.2 with the Intel app under Rosetta.

## Limits

This review challenges one corrected historical fixture and six bounded metadata variations.
It does not claim coverage of all historical archive versions, encrypted libraries, power loss, disk failures, or remote-only notes.
It verifies application decoding and rewriting in memory; the permanent regression covers the local directory migration path.
It adds no production code or permanent regression changes.
