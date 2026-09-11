# Round 2: backup-root contracts and lazy wiki prefixes

This Ousterhout-inspired review covers frozen commit `3a3dc4fb7194b5ea7189295a7bbd17393bb32038` in PR 29.
The review focuses on API contracts and the two round-one corrections.
It is not a review by John Ousterhout.

## Finding: P2 — Create the development namespace through the backup-store contract

Location: `Sources/Storage/NVBackupController.m:201`.

A newly selected custom folder cannot receive its first development backup.
`rootURLWithError:` appends `nvALT Development` to the selected parent, but does not create that child.
`beginBackupAtDate:manual:` then requires the destination's immediate parent to exist at lines 255–263.
That immediate parent is now the absent development child.
Both automatic and manual backups return the unavailable-folder error before snapshot capture.
The retry repeats the same failure.

The native probe reproduced this failure with a real bookmark to an existing temporary directory.
The development process reached snapshot capture only after the probe manually created the development child.
Release and missing-flavor processes reached snapshot capture without that extra directory.

The root contract needs to distinguish the selected parent from the application namespace beneath that parent.
The store also requires the destination to be an immediate child of `existingRoot` in `Sources/Storage/NVBackupStore.m:117`.
A correction must preserve the selected parent's identity and unavailable-volume protection through namespace creation and snapshot publication.
Removing the root check alone loses that protection.

## Simplicity and identity behavior

`NVAppIdentity.h` remains a small source of truth for the build flavor and note scheme.
The runtime decision uses bundle metadata, so a copied bundle identifier does not change the flavor.
Absent flavor metadata retains release behavior.
The reviewed changes add no controller owner or lifecycle coordinator.

The wiki prefix belongs inside one scan invocation.
Its lazy initialization avoids bundle lookup for scans without accepted links.
It also avoids a global cache or new invalidation rules.
No actionable wiki-prefix finding emerged from the focused checks.

## Executable evidence

Run from this worktree:

```sh
python3 -B Tests/DevelopmentBuildReview/round2/ousterhout/run.py
```

The runner passed 352 assertions across three native arm64 processes: development, release, and missing flavor metadata.
`results.json` contains the process output, macOS version, Xcode version, and frozen commit.
The runner extracts all production code with `git show` at the recorded commit.

The backup check covers default roots, missing support directories, real custom bookmarks, first-backup preflight, removed bookmarked parents, file bookmarks, and invalid bookmark bytes.
Both automatic and manual preflight paths run for each case.
The native filesystem and bookmark APIs operate only on temporary fixture paths.
The probe observes the exact production preflight at the snapshot-capture boundary.

The wiki check covers empty text, unmatched brackets, rejected whitespace, line breaks, restricted scan ranges, Unicode, and reserved URL characters.
Rejected scans perform zero scheme lookups.
Two accepted links share one prefix lookup within each scan.
A second scan performs one new lookup.

## Limits

The backup probe replaces the application-support provider with a temporary path provider.
It also replaces library ownership, error storage, scheduling, and the code after backup preflight with observation points.
It does not run snapshot publication, retention, the timer, or the complete application.
The runner checks that the probe imports neither keychain operations nor `NSUserDefaults`.
The checks use no personal preferences, keychain items, notes, or GUI session.
No production files changed during this review.
