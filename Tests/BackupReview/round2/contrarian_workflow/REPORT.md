# Round 2: contrarian workflow review

PR: https://github.com/fastducduc/nv/pull/8

Production baseline: `a89f8351646f824f51ed6ea80b94f724f37d0303`.
Initial feature: `30c3cf816c80e4ff957223d55f22b36074880ef1`.
PR base: `119c453`.
Host: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), arm64.

This independent review challenges backup controls, cancellation behavior, and unnecessary state changes.
It covers manual backups with the schedule disabled and each restore transition.
The review found one P3 status defect.

## Finding

**P3: An obsolete restore decode result can replace the current library's error.**

Location: `Sources/Storage/NVBackupController.m:401-404`.

**Reachability limit:** The probe injects a library switch through the decoder callback.
It does not establish an ordinary menu action that changes libraries during the full application's password dialog.
The result establishes a defect in the coordinator's explicit context contract.
It does not establish note loss, an incorrect restore, or a normal UI reproduction.

The coordinator saves its context before a restore and checks that context after archive decode.
If a library switch occurs during decode, that check correctly prevents the destination dialog and restore.
However, the same branch still writes the obsolete decode error into the new library's status.
A successful obsolete decode passes `nil` to `setError:` and clears the new library's existing error.

The probe starts a restore for library A.
During decode, its callback attaches library B with an unavailable backup destination.
The callback checks that B initially reports the unavailable destination.
When the obsolete decode returns, the coordinator changes that status:

| Obsolete decode result | Current library B status after completion |
| --- | --- |
| Success | The unavailable-destination error disappears. |
| Error | `Original library decode failure` replaces the unavailable-destination error. |

The coordinator preserves B's identity and settings in both cases.
It opens no destination dialog and performs no restore.
The defect affects the displayed reason that backups cannot proceed.

A separate early return for an obsolete context preserves the current status.
The temporary mutation adds that return before the decode-error branch.
The mutation passes both status-isolation assertions and all other workflow assertions.

## Executable evidence

Run these commands from `/Users/duc/dev/nv`.

| Command | Result |
| --- | --- |
| `python3 Tests/BackupReview/round2/contrarian_workflow/run.py` | Exit 0. Passed 40 new assertions, including two explicit defect reproductions. |
| `python3 Tests/BackupReview/round2/contrarian_workflow/run.py --expect-context-isolation` | Exit 1. Failed at `Stale decode cannot replace the current library's error`. |
| `python3 Tests/BackupReview/round2/contrarian_workflow/run.py --expect-context-isolation --context-mutation` | Exit 0. Passed all 40 assertions with the temporary context guard. |

The [probe](restore-flow.m) includes the existing coordinator fixture and adds a new entry point with new assertions.
The [runner](run.py) compiles the complete production `NVBackupController.m` without extraction.
Each process has a 30-second timeout.
The runner removes its temporary sources, binaries, and disposable files after each run.

The assertions establish these successful behaviors:

- Disabled scheduling remains idle after retention changes and an overdue interval.
- Explicit manual requests each publish a snapshot, including unchanged content.
- Manual success preserves disabled scheduling and does not start an automatic follow-up.
- Snapshot selection cancellation starts no worker or decode operation.
- Password cancellation clears the busy state without an error or application restore call.
- Destination cancellation preserves the active library and settings.
- A manual request during restore cannot start a competing backup.
- Application restore rejection clears the busy state and shows the application error.
- Library changes during snapshot selection, queued archive reads, and destination selection reject obsolete work.
- A library change during decode prevents the destination dialog and application restore call.

## Evidence boundaries

The probe runs the complete production backup coordinator on the native host architecture.
It uses the existing deterministic clock, manual operation queues, library fixture, store fixture, and memory defaults.
The store fixture reads disposable bytes and supplies its documented successful-read contract.
This probe does not check real snapshot checksums, archive decoding, encryption, filesystem transactions, or journal recovery.

Scripted objects replace file panels and record each modal boundary.
A scripted archive decoder supplies success, cancellation, and failure results.
A recording application object receives the final restore request and supplies success or failure.
These collaborators establish coordinator ordering and status behavior. They do not establish native dialog behavior or application replacement.

No Intel application was launched because the host stalls before application startup.
No personal notes, production sources, or committed files changed during this review.
This report does not duplicate the other round-two findings about Preferences closure, deletion ownership, or retry intervals.
