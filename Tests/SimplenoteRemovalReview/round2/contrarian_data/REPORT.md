# Round 2: encrypted data preservation and passive downgrade

No actionable introduced defect found in this scope.
The old app's encrypted local archive remains readable after Simplenote removal and after two current-app rewrites.
The old app can also read those rewritten local notes without recovering remote account or sync state.

Reviewed commit: `b418d8466d2936de0fb62c8556ce3e0de4b9f106`.
Its production source is unchanged from `f38a8cb3f1e5f74c57cfe5e8d5791f364201f1cb`.
Comparison base: `9693356`.
Environment: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), x86_64 app.

## Original executable evidence

[generate.inc](generate.inc) writes one encrypted note and one remote deletion record with the actual old app.
The old app comes from commit `65e1608ff4e9977ec2d7a09297739152f9cfc935`.
Its NoteObject, NotationPrefs, and FrozenNotation sources match the comparison base.
The fixture has a recognized enabled `SN` account and dirty note metadata.
It uses a public synthetic passphrase defined in [prefix.h](prefix.h).

The note contains UTF-32LE source with a transport BOM and a separate literal leading U+FEFF.
Its body also includes Japanese characters, an emoji, CRLF, a tab, and accented characters.
The oracle checks exact source bytes, BOM, source characters, UUID, journal sequence, title, tags, dates, and local syntax.
These expectations are independent constants in the probe, rather than a snapshot produced by the current encoder.

| Execution | Result | Evidence |
| --- | --- | --- |
| Old producer and old self-read | 24 checks passed | [generate.log](generate.log) |
| Current reader, then two encrypted rewrites | 56 checks passed | [reader.log](reader.log) |
| Old reader of both current rewrites | 38 checks passed | [downgrade.log](downgrade.log) |

Every fresh read first uses the wrong synthetic passphrase.
The verifier rejects it without installing a master key.
An attempted read then returns nil and `kNoAuthErr`, preserving the ciphertext for retry.
The correct passphrase subsequently restores the exact local note.
These six rejected reads are the failure controls; their error messages in the logs are expected.

Both current rewrites use a new data-session salt and retain encryption.
The same correct passphrase reads them, and the wrong passphrase still fails.
Their outer archives omit obsolete account and deletion-history fields.
Their decrypted note payloads omit `syncServicesMD`.
This supports the retained preference decoding at [NotationPrefs.m:150](../../../../Sources/Preferences/NotationPrefs.m#L150),
the verifier at [NotationPrefs.m:427](../../../../Sources/Preferences/NotationPrefs.m#L427), and
the note decryption path at [FrozenNotation.m:112](../../../../Sources/Storage/FrozenNotation.m#L112).

The storage boundary is unchanged: original source bytes are inside encrypted note data.
The UUID-keyed syntax dictionary remains in unencrypted library preferences.
The review does not claim that syntax or note UUIDs are secret.
Literal source-byte searches also pass, but those searches alone are not a confidentiality proof.

## Isolation and limits

The old `setPassphraseData:inKeychain:NO` setter still calls legacy keychain cleanup.
The producer uses a test subclass that intercepts only that cleanup boundary.
It inherits the real passphrase derivation and encryption methods and archives as the production `NotationPrefs` class.
The old self-read confirms that production class identity.
No keychain identifier is allocated, and no system keychain call runs.
The readers use production preferences and need no cleanup interception.

All executions use copied apps, temporary notes, isolated defaults, and the shared GUI lock.
They never start a remote service or access real notes, accounts, credentials, or network resources.
The passphrase is supplied to the verifier and explicit archive reader; password sheets are outside this test.
Journal crash recovery, different passwords, other encryption settings, and arbitrary archive corruption are outside this bounded history.
Passive old-reader success does not promise that remote syncing can resume after downgrade.
No production or permanent regression files were changed.

## Reproduction and artifacts

Run these commands from the repository root, in order:

```sh
NV_ENCRYPTED_REVIEW_DIRECTORY="$PWD/Tests/SimplenoteRemovalReview/round2/contrarian_data" \
python3 Tests/ViewControlsReview/run-probe.py \
  --app build/SyntaxFlickerReview/fix.app \
  --prefix Tests/SimplenoteRemovalReview/round2/contrarian_data/prefix.h \
  --probe Tests/SimplenoteRemovalReview/round2/contrarian_data/generate.inc

NV_ENCRYPTED_REVIEW_DIRECTORY="$PWD/Tests/SimplenoteRemovalReview/round2/contrarian_data" \
python3 Tests/ViewControlsReview/run-probe.py \
  --app build/SimplenoteRemovalReview/round1.app \
  --prefix Tests/SimplenoteRemovalReview/round2/contrarian_data/prefix.h \
  --probe Tests/SimplenoteRemovalReview/round2/contrarian_data/checks.inc

NV_ENCRYPTED_REVIEW_DIRECTORY="$PWD/Tests/SimplenoteRemovalReview/round2/contrarian_data" \
python3 Tests/ViewControlsReview/run-probe.py \
  --app build/SyntaxFlickerReview/fix.app \
  --prefix Tests/SimplenoteRemovalReview/round2/contrarian_data/prefix.h \
  --probe Tests/SimplenoteRemovalReview/round2/contrarian_data/downgrade.inc
```

Fresh encryption salts change artifact hashes on regeneration.
The checked artifacts have these SHA-256 values:

| Artifact | Bytes | SHA-256 |
| --- | --- | --- |
| old-encrypted.notation | 4,964 | `9451a9b21615c54f03cc8e7f1cecd2de4e737a1ebdfcb98ea98f9417511c7f6f` |
| rewritten-1.notation | 3,812 | `dae8be416e907488e37f0579329569454a0d41f0a468e1f6c40329ab7bba1e8c` |
| rewritten-2.notation | 3,812 | `211431a09d9418ec9e73517122b0f1cd319deefa1bab901dbcbfe4f088823cfc` |

Old executable: `ee8e9ca27c99d55ff867afabd49e75c12f5548f49ac93dc733f514f477cac365`.
Current executable: `d61aea6619f6c4322efac164d7409ac131aa0ce2a8760d874850c34443331ede`.
