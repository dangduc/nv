# Round 3: backup directory correctness

This review uses a Torvalds-inspired engineering perspective. It is not a review by Linus Torvalds.

Reviewed commit: `47d18f43cadb1a2eeeed9c7fbe379795c76faae7`.
The native descriptor checks passed on arm64 and x86_64 through Rosetta.
One source-level root-identity finding remains.
The host used macOS 26.5.2 (25F84) and Xcode 26.6 (17F113).

## Finding: P2 — Canonicalize the selected parent before appending its namespace

Location: `Sources/Storage/NVBackupController.m:201`.

`rootURLWithError:` appends the Development namespace and then calls `CanonicalURL` at line 202.
That helper resolves symbolic links in the combined URL.
The publication path later derives `existingRoot` from this result at lines 256–257.
Deletion repeats that derivation at lines 380–381.

The captured parent therefore comes from the canonicalized destination, rather than directly from the canonicalized bookmarked parent.
These operations are not equivalent when canonicalization changes the namespace component.
The worker receives the derived parent and its matching identity, so its metadata checks cannot establish the original bookmarked-parent relationship.

Canonicalize the bookmarked parent first, then append the fixed namespace as a path component.
This preserves the selected root as the identity anchor and leaves namespace entry validation with the worker's existing descriptor checks.

This finding follows source data flow and the explicit native URL operation.
The review did not construct a redirection fixture or demonstrate resulting filesystem effects.
The executable tests below address descriptor and rejection behavior under ordinary disposable paths.

## Native evidence: directory ownership and error paths

The probe compiles the complete production `NVBackupStore.m` into its translation unit.
This exposes the two static helpers without a second implementation.
The runner first compares the store, header, and controller against the reviewed commit and records their hashes.

Each architecture passed 1,603 assertions:

- 52 successful operation-directory opens cover initial creation, existing directories, release paths, Development paths, and retries.
- 226 rejected opens cover invalid namespace metadata, invalid or stale identities, malformed root metadata, mismatched destination paths, missing children, and regular-file entries.
- Native `proc_pidinfo` provides 634 descriptor samples. The process starts and finishes with three descriptors.
- Each successful operation retains exactly its returned descriptor. That descriptor has `FD_CLOEXEC` and names the requested directory.
- Each rejection leaves the descriptor count unchanged. Eight direct child-helper cycles preserve the caller's borrowed parent descriptor.
- Two injected `fsync` failures cover namespace creation and library-child creation. Both paths release descriptors and permit a successful retry.
- Six tiny public publications and six maintenance calls also leave the descriptor count unchanged.

The probe wraps only `fsync`, delegates normal calls to the real function, and injects `EIO` at the two selected creation boundaries.
It uses real native directory, file, descriptor, publication, and maintenance operations for the remaining checks.
It does not simulate storage-device behavior.

Invalid metadata and noncreating operations leave the selected fixture root empty.
The removed-root case returns `ENOENT` and never recreates the selected root.
Release keeps its direct UUID child, while Development uses its namespace child.
Both public destinations contain three snapshots after the bounded run.

The helpers have a consistent ownership contract in these cases.
`NVOpenBackupChild` borrows its parent and returns an owned child.
`NVOpenOperationDirectory` closes intermediate parents and returns only the final owned descriptor.
No descriptor-lifecycle defect emerged at `NVBackupStore.m:108–163`.

## Reproduction and limits

Run from the repository root:

```sh
python3 Tests/DevelopmentBuildReview/round3/torvalds/run.py
```

The adjacent `results.json` contains source hashes and both native summaries.
Generated executables and logs remain in `build/DevelopmentBuildReview/round3/torvalds/`.
Each compile or native process has a 45-second timeout.
The runner deletes its disposable folders after each process.

The review uses no user notes, preferences, keychain data, or GUI session.
It makes no production changes and creates no symbolic links or concurrent replacement fixtures.
It does not establish correctness under power loss, every filesystem error, descriptor exhaustion, or older macOS versions.
The controller finding remains source-level evidence, separate from the passing native store checks.

## Post-fix source verification

The working-tree correction resolves the P2 source finding.
`rootURLWithError:` now canonicalizes the bookmarked parent at line 202, appends the Development namespace, and returns without recanonicalization.
`checkedDestinationWithError:` canonicalizes a separate URL for the notes-containment comparison but returns the original destination at line 219.

Publication removes the UUID and Development namespace components at lines 258–259 before capturing the parent's identity.
Deletion uses the same derivation at lines 382–383.
Both paths now derive the original canonicalized selected parent.
The worker receives the namespace separately and retains its existing entry checks.

Release still returns the same canonicalized selected root because it appends no namespace.
The default destination branch is unchanged.
`NVBackupStore.m` is byte-identical to the frozen review commit.

This verification inspected the working-tree source and diff only.
It adds no native execution or redirection fixture.
The earlier native results still describe commit `47d18f4`.
Build and integration results belong to the root review task.
The verified controller SHA-256 is `e1ec50b546ce18badd28087e292659b9191490cc65ea6a06a0427e137ce08cba`.
