# Round 2 controller and store fixes

These changes address three PR #8 comments:

- [P2 deletion ownership, comment 5593991502](https://github.com/fastducduc/nv/pull/8#issuecomment-5593991502).
- [P3 retry deadline, comment 5594036293](https://github.com/fastducduc/nv/pull/8#issuecomment-5594036293).
- [P3 stale decode status, comment 5594089742](https://github.com/fastducduc/nv/pull/8#issuecomment-5594089742).

The review baseline was `a89f8351646f824f51ed6ea80b94f724f37d0303`.

## Resulting behavior

Explicit plaintext deletion now requires metadata with the captured active library UUID.
For a selected root, the controller also captures its device and inode before it queues the operation.
The store uses the same directory boundary as maintenance, with directory creation disabled.
It rejects a missing destination, a changed selected root, or a foreign library owner.
Matching ownership still permits deletion of complete plaintext snapshots and preserves encrypted or unrecognized packages.
All production callers and store fixtures use the new required metadata argument.

The controller now records the intentional delay with each next-attempt date.
The clock correction compares the remaining wait with that delay.
A supported 60-second interval therefore preserves a 300-second failure deadline.
An actual backward clock change restarts the bounded wait for that operation.
After success, ordinary checks again use the selected interval.
The same rule covers capture, destination, publication, and maintenance failures.

A separate return after archive decode rejects a stopped controller or an obsolete library context.
That return preserves the current library's status before the decoder's error branch can run.
Obsolete success and obsolete failure open no destination dialog and perform no restore.

## Positive regressions

Commands run from the repository root:

| Command | Result |
| --- | --- |
| `python3 Tests/BackupStore/run.py` | 376 assertions passed. |
| `python3 Tests/BackupCoordinator/run.py` | All coordinator assertions passed. |
| `python3 Tests/BackupReview/round1/torvalds/run.py` | 691 checks passed. Descriptors: 3 to 3. |
| `python3 Tests/BackupReview/round2/torvalds/run.py` | 832 checks passed. Descriptors: 3 to 3. |
| `python3 Tests/BackupReview/round2/luu/run.py` | Both retry deadlines remain 300 seconds at intervals 900 and 60. All read, settings, and memory assertions passed. |
| `python3 Tests/BackupReview/round2/contrarian_workflow/run.py` | 40 workflow assertions passed, with both current-library errors preserved. |
| `python3 Tests/BackupReview/round2/torvalds/check-production.py` | Strict compilation and static analysis passed for both production files on arm64 and x86_64. Analyzer diagnostics: zero. |
| `git diff --check` | Passed. |

The coordinator now records deletion metadata and tests a library switch before the queued deletion completes.
Its new retry cases cover capture, publication, and destination failures at the 60-second interval.
The integrated Luu probe covers unchanged maintenance through the actual store.
Each retry case includes ordinary forward ticks and an actual backward clock change.

The store tests cover foreign ownership, absent directories, and a selected root that moves before deletion starts.
They also cover a replacement directory at that selected path.
The replacement root remains empty, and the original root retains its complete snapshots.

## Negative mutation checks

Each command creates a temporary production-source copy and restores one defect.
The corrected regression exits with status 1 at the expected assertion.

| Command | Expected assertion failure |
| --- | --- |
| `python3 Tests/BackupReview/round2/torvalds/run.py --deletion-mutation` | `deletion rejects fixture` |
| `python3 Tests/BackupReview/round2/luu/run.py --retry-mutation` | `minimum interval preserves the full five-minute deadline` |
| `python3 Tests/BackupReview/round2/contrarian_workflow/run.py --regress-context` | `Stale decode cannot replace the current library's error` |

The default review commands now require corrected behavior.
The original reports retain their historical baseline results.
The mutation commands leave production sources unchanged and delete their temporary files after each run.

## Limits

The host runs macOS 26.5.2 (25F84) and Xcode 26.6 (17F113).
The native probes do not run the shipping Intel application, full archive decoder, or application restore transaction.
Scripted collaborators supply the coordinator's clocks, queues, alerts, panels, libraries, and decoder results.
The store checks use disposable local files.
They do not establish persistence after power loss or behavior on remote filesystems.

The Luu fast-math build retains the previously reported `NAN` warning in settings validation.
Both numeric-settings probes still reject all 30 invalid inputs.
Strict production compilation uses warnings as errors, without fast math.
It excludes unused callback parameters and deprecated declarations from those errors.
