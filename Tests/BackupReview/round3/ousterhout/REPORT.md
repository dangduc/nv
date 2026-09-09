# Round 3: ownership and interface review

PR: https://github.com/fastducduc/nv/pull/8

This final review uses an Ousterhout-inspired lens. It does not represent John Ousterhout.
The review covers shared-library ownership, browser attachment, nested command routing, and termination permission.

Production baseline: `8ebbcb511415958f700ca54e4216e6447464d284`.
PR base: `119c453`.
Host: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), arm64.
The production working tree had no changes during this review.

## Result

**No new actionable finding within this focused scope.**

The coordinator keeps the shared library as its explicit owner boundary.
The prepared replacement path closes old editing sessions without another commit.
It attaches all visible browsers and the closed initial browser before restored preference callbacks.
Those callbacks remain inside the command guard.

Normal replacement retains its existing commit contract.
Normal commands reach the active browser and the selected library after the restore owner clears its guard.
Nested library calls restore the originating browser after an exception.
Termination permits checkpoint calls only during its callback and clears that permission after an exception.

## Source boundaries

| Source | Contract covered |
| --- | --- |
| `Sources/Application/NVApplicationController.m:194` | Public replacement cannot interrupt an active backup restore. |
| `Sources/Application/NVApplicationController.m:198` | Normal and prepared replacement use distinct closure contracts. |
| `Sources/Application/NVApplicationController.m:214` | All browsers attach before restored preference callbacks. This includes the closed initial browser. |
| `Sources/Application/NVApplicationController.m:247` | Restore owns the command guard through replacement or successful journal resume. |
| `Sources/Application/NVApplicationController.m:365` | Nested library calls restore the previous browser in `@finally`. |
| `Sources/Application/NVApplicationController.m:432` | Termination owns an exception-safe permission for checkpoint calls. |
| `Sources/Application/NVApplicationController.m:487` | Normal command routing retains the active-browser and global-display behavior. |
| `Sources/Storage/NotationController.m:742` | Restore preparation refuses active ODB sessions before journal closure. |

These references identify reviewed boundaries. They are not findings or severity assignments.

## Executable evidence

Run these commands from `/Users/duc/dev/nv`.

| Command | Result |
| --- | --- |
| `python3 Tests/BackupReview/round3/ousterhout/run.py` | Exit 0. Passed 50 new ownership assertions and rejected four unsafe mutations. |
| `python3 Tests/BackupReview/round1/ousterhout/run-restore.py` | Exit 0. Passed 26 restore assertions and rejected three unsafe mutations. |
| `python3 Tests/BackupStore/run-teardown.py` | Exit 0. Passed four teardown assertions and rejected three unsafe mutations. |
| `python3 Tests/BackupReview/round2/ousterhout/run-pane.py` | Exit 0. Passed 89 assertions for pane lifetime and complete policy updates. |

The new [runner](run.py) extracts current production methods on each run.
It compiles the [ownership fixture](ownership.m.in) with `-Wall -Wextra -Werror` and exclusions for unused fixture parameters and deprecated APIs.
Each compilation has a 30-second limit. Each executable has a 15-second limit.
The runner removes generated sources and binaries after completion.
Default execution requires the corrected behavior.

The new assertions cover these contracts:

- Normal replacement finishes visible browsers and commits cached editing sessions.
- Prepared replacement closes sessions without another commit and uses the prepared resource closure.
- Both replacement paths attach the closed initial browser to the selected library.
- Preference callbacks observe all browsers on the replacement library and cannot issue a library command during restore.
- Backup ownership follows the selected library after browser and preference attachment.
- Normal actions reach the active browser, and global display actions reach both visible browsers.
- A nested exception restores the outer browser. The outer return then restores the preexisting browser.
- A rejected invocation preserves the previous operation owner.
- A termination exception clears checkpoint permission and keeps the restore guard active.
- A later termination attempt receives its own checkpoint permission and closes cached sessions.

Each mutation changes only a generated temporary source file.
The runner rejected a second prepared commit, an omitted initial-browser attachment, a lost outer browser, and persistent termination permission.

## Limits

The new probe executes extracted coordinator methods with native Foundation invocation and exception behavior.
Its library, browsers, editing sessions, preference callbacks, and backup controller are recording collaborators.
The probe does not load browser nibs, decode archives, or execute journal storage.
Its explicit guard release represents the restore owner after a completed transition.
The reused restore probe executes the production restore method with a replacement and recovery fixture.

The pane probe uses native AppKit windows and field editors with fixture backup settings.
AppKit emitted XPC connection messages during that probe. All 89 assertions completed with exit 0.

Source inspection covered the modal recovery loop and ODB preflight contract.
This review did not add a separate modal or ODB event probe.
The detailed recovery and ODB regression evidence remains in the round 2 correction record.

The Intel application stalls before `main` on this host.
This review did not launch the Intel application or establish full desktop recovery behavior.
No production source, personal notes, or application settings changed during this review.
