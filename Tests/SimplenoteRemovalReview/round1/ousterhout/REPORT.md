# Round 1: archive and model boundaries

This review uses John Ousterhout's design principles as a lens. It does not represent his participation or endorsement.

Reviewed commit: `f38a8cb3f1e5f74c57cfe5e8d5791f364201f1cb`.
Comparison source: `9693356` (`origin/master` at review start).
The frozen current app is `build/SimplenoteRemovalReview/round1.app`.
The comparison app is `build/SyntaxFlickerReview/fix.app`, built from `65e1608`.
Its model and archive implementation matches the comparison source.

## Result

No actionable introduced defect found in this bounded scope.

The smaller `LogNote` interface separates journal identity and ordering from remote account metadata.
Its implementation preserves the existing UUID equality, hashing, and sequence comparison behavior.
The archive readers contain the compatibility details, so callers no longer supply obsolete deletion sets or account dictionaries.

The native probe passed **98 assertions in each app**, including two harness setup assertions.
The baseline provides a behavioral control: it visits every injected obsolete payload and retains the source behind a tombstone.
The current implementation skips those payloads and allows the source to deallocate immediately.

## Evidence

[prefix.h](prefix.h) defines an archive envelope that calls each real object's encoder and adds an observable obsolete field.
The envelope archives as the real model class. Its observer increments a counter only if the decoder visits the obsolete object.
[checks.inc](checks.inc) runs against the actual model implementations in copied apps.

| Boundary | Observation in current app | Source |
| --- | --- | --- |
| `NoteObject` | Skips remote metadata, omits it on rewrite, preserves source characters, title, tags, UUID, and sequence | [NoteObject.m](../../../../Sources/Model/NoteObject.m#L543) |
| `DeletedNoteObject` | Skips remote metadata and copies identity without retaining the source | [DeletedNoteObject.m](../../../../Sources/Model/DeletedNoteObject.m#L28) |
| `NotationPrefs` | Skips the account payload, marks preferences for rewrite, preserves local storage settings | [NotationPrefs.m](../../../../Sources/Preferences/NotationPrefs.m#L143) |
| `FrozenNotation` | Skips remote deletion history, preserves the packed local note, omits the old field on rewrite | [FrozenNotation.m](../../../../Sources/Storage/FrozenNotation.m#L26) |

The probe also changes and releases a protocol-only source after creating its tombstone.
The copied UUID and high unsigned sequence remain valid.
It then advances that sequence 32 times, checking keyed and sequential archive copies and ordering after each advance.
Both formats preserve the values, and the source deallocates exactly once.

Outputs: [current.log](current.log), [baseline.log](baseline.log). Both commands exited zero.

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/SimplenoteRemovalReview/round1/ousterhout/checks.inc \
  --prefix Tests/SimplenoteRemovalReview/round1/ousterhout/prefix.h \
  --app build/SimplenoteRemovalReview/round1.app \
  > Tests/SimplenoteRemovalReview/round1/ousterhout/current.log 2>&1

python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/SimplenoteRemovalReview/round1/ousterhout/checks.inc \
  --prefix Tests/SimplenoteRemovalReview/round1/ousterhout/prefix.h \
  --app build/SyntaxFlickerReview/fix.app \
  --launch-arg NVReviewBaseline \
  > Tests/SimplenoteRemovalReview/round1/ousterhout/baseline.log 2>&1
```

The final fixture nests the observer inside an account-shaped dictionary for both runs.
An initial current-only run used a shallower dictionary and also passed; the final logs use the identical nested fixture.
No production files were changed. The harness uses temporary notes and a copied app.
No account, credential, remote service, or user note is needed.

## Limits

This probe tests archive boundaries and local ownership, not full journal crash recovery or network isolation.
It supplements the fixed old-app archive regression; it does not replace that fixture.
It does not prove compatibility with every historical archive, malformed data, sequence wraparound, or unsupported platform.
The removed remote fields are tested with observable collection payloads, not real account records.
