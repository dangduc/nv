# Round 3: complete custom-backup publication

This final Ousterhout-inspired review covers frozen commit `47d18f43cadb1a2eeeed9c7fbe379795c76faae7` in PR 29.
It is not a review by John Ousterhout.

No actionable findings.
The complete application checks passed for the round-two correction.
Development now creates its absent namespace and UUID folder during first custom publication.
Release keeps its existing custom layout.
Both applications retain their custom bookmark and decode the same snapshot after relaunch.

The selected parent and the namespace now have separate roles in the store contract.
The coordinator captures the selected parent's identity before the worker starts.
The store checks that identity before it creates the namespace and UUID children through directory descriptors.
This contract resolves the earlier conflict between an absent application namespace and the required existing selected parent.
The change adds no controller owner or lifecycle coordinator.

## Executable evidence

Run from this worktree with access to the active desktop:

```sh
python3 -B Tests/DevelopmentBuildReview/round3/ousterhout/run.py
```

The runner passed 252 assertions across four application processes.
Development and release ran concurrently during the first phase and again after relaunch.
The applications used x86_64 binaries under Rosetta on macOS 26.5.2, with Xcode 26.6.
`results.json` records the executable hashes, process reports, snapshot paths, and environment.
`output/` contains the application logs and window images.

| Phase | Development | Release |
| --- | ---: | ---: |
| First publication | 85 | 81 |
| Relaunch | 43 | 43 |

The first phase performs these checks in each complete application:

1. Publish a note through the unchanged default support destination.
2. Read the package with `NVBackupStore` and decode the actual `FrozenNotation` payload.
3. Select a real bookmark to an existing shared custom parent with no UUID directory.
4. Check that the development namespace is absent before publication.
5. Run the manual backup action and decode its actual published payload.
6. Repeat first publication in a second fresh parent through the automatic due-check entry point.
7. Save the custom bookmark and snapshot settings before normal termination.

After relaunch, both applications retain the selected custom parent, destination path, and automatic snapshot path.
The store reads that snapshot again, and the archive decodes to the expected note title and body.
The original harness also checks distinct support paths, notes, preferences, caches, edit directories, and keychain service names.
The window images show each disposable note and its expected editor color.

## Test boundaries and limits

The runner adapts the isolation harness from the frozen commit through `git show`.
It injects observation and fixture code into copies of the complete built applications.
The real coordinator, snapshot capture, metadata transfer, asynchronous worker, store publication, and archive reader run unchanged.

The fixture creates the native bookmark and applies the same settings changes as `chooseDestination:`.
It does not present the folder picker.
The automatic check calls `checkForBackupAtDate:` directly, so this run does not wait for the 30-second timer.
It does not repeat the independent store checks for symlink substitution, removed volumes, or retention.

The harness redirects operating-system base paths to a temporary directory beneath the worktree's `build` directory.
Copied bundles use unique preferences domains, and keychain calls use the existing test interceptors.
The shared GUI lock covers all four processes.
The runner removes the copied applications, temporary notes, backup packages, and generated preferences domains after completion.
No production files changed during this review.

The first sandboxed attempt aborted inside macOS application registration before application startup.
The same runner passed with desktop access outside that sandbox.
This launch constraint does not indicate a backup failure.
