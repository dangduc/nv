# Round 3: first publication and reopened backup histories

No actionable finding in the two bounded hypotheses.
All 169 checks passed across five headless process commands at frozen commit `47d18f43cadb1a2eeeed9c7fbe379795c76faae7`.
This review uses a Kingsbury-inspired focus on state histories and persistence boundaries.

## Executed evidence

Command: `python3 -B Tests/DevelopmentBuildReview/round3/kingsbury/run.py`.

H1 passed. Only the selected parent existed before publication.
The release and development fixtures used the same copied library UUID and different payload bytes.
The development namespace did not exist before its first publication.
The actual backup store created both `nvALT Development` and its UUID child, then published a readable snapshot.

H2 passed. Each command ran in a new process and read the prior snapshot identifiers and bytes from an independent checkpoint.
The store validated every archive checksum, and the probe compared its exact bytes with the expected flavor payload.

| Process command | Release snapshots afterward | Development snapshots afterward | Checks |
| --- | ---: | ---: | ---: |
| Release publishes five snapshots | 5 | 0 | 31 |
| Development first publication and four more snapshots | 5 | 5 | 43 |
| Development retention | 5 | 3 | 36 |
| Release plaintext deletion, then republication | 1 | 3 | 36 |
| Development plaintext deletion | 1 | 0 | 23 |

Every operation preserved every peer snapshot identifier and archive byte.
Release deletion preserved all three development snapshots before republication.
The final development deletion preserved the new release snapshot after a process reopen.

## Test boundary

The runner compiles the full frozen `NVBackupStore.m`, its header, and `NVAppIdentity.h` without test flags or fault injection.
Small headless bundles supply release or development metadata through the production identity helper.
The fixture supplies caller metadata with the actual selected parent, its original device/inode identity, and the fixed development namespace.
No fixture code creates the namespace or UUID directories.

The selected-parent identity remains the same across processes.
The checkpoint stores expected snapshot identifiers and bytes separately from the backup packages.
The archive bytes are disposable payloads. This probe does not decode a library archive.

## Artifacts and limits

- `results.json`: frozen commit, process history, assertion counts, and production hashes.
- `runtime-output.log`: all five process results.
- `compile.log`: empty, because compilation produced no diagnostics.
- `history.m` and `run.py`: the executable evidence.

The run used only disposable files under this review directory. The runner removed them afterward.
It did not read or write preferences, user notes, or keychain items. Every process asserted that no `NSApplication` instance existed.
Production hashes matched before and after the run. Earlier review rounds remained unchanged.

These checks exercise the real store with independently supplied caller metadata.
They do not execute the full backup controller or application startup.
Root unavailability, root replacement, concurrent failures, and encrypted archive decoding remain outside this review.
