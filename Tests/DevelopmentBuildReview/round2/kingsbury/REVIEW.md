# Round 2: persistence and retention separation

No actionable finding in the two bounded hypotheses.
The review uses frozen commit `3a3dc4fb7194b5ea7189295a7bbd17393bb32038`, after the Round 1 collision at `2dbfd46`.
This is a Kingsbury-inspired review of state histories and persistence boundaries.

## Executed evidence

Command: `python3 -B Tests/DevelopmentBuildReview/round2/kingsbury/run.py`.

H1 passed across nine process commands. Independent flavor settings, alias bytes, and physical-library claims survived relaunch.
Both copies retained the same library UUID but resolved to separate destinations:

- Release: `<custom root>/<library UUID>`.
- Development: `<custom root>/nvALT Development/<library UUID>`.

Each destination stayed identical after another process started.
The same-domain copy control still renewed its library UUID.
Every controller process asserted that no `NSApplication` instance existed.

H2 passed 61 checks in one additional process with the actual frozen `NVBackupStore` implementation.
The store published five distinct archives per flavor, under the destinations from H1.
Development retention reduced its snapshots from five to three and preserved every release snapshot identifier and archive byte.
Release retention then reduced its snapshots from five to three and preserved every remaining development snapshot identifier and archive byte.
Both histories used the same copied library UUID.

## Test boundary

The controller fixture compiles selected verbatim production methods and the frozen `NVAppIdentity.h` header.
It substitutes small library and preference objects for application-owned objects.
Real bundle metadata, Foundation bookmarks, and separate `NSUserDefaults` processes supply the app flavor and persisted settings.

The retention fixture compiles the full frozen backup store without test flags or fault injection.
Its metadata includes each existing parent directory and its actual device/inode identity.
It reads archives through the store's checksum validation and compares exact bytes.

The runner prepares both parent directories before publication.
This deliberately excludes creation of the missing development child directory, which another reviewer covers.
The archive bytes are disposable payloads. This fixture does not decode library archives.

## Artifacts and limits

- `results.json` records resolved destinations, the process history, and source hashes.
- `runtime-output.log` records the successful process commands.
- `retention-output.log` records the 61-check retention result.
- `compile.log` is empty because both compilations produced no diagnostics.
- `probe.m`, `retention.m`, and `run.py` contain the executable evidence.

The initial sandbox run could not synchronize the generated test preference domains.
The successful run used permission for those unique domains and removed them afterward.
A temporary-path assertion also required correction because Foundation and Python represented `/var` and `/private/var` differently.
The successful run used a disposable directory under this review folder and removed it afterward.

No production files, production preference domains, user notes, or keychain items changed. No GUI started.
The before/after production hashes match the captured frozen source hashes.
These checks do not cover first-backup directory creation, actual application startup, encrypted archive decoding, or failures during concurrent publication.
