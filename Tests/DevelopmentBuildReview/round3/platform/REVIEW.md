# Round 3: selected-parent identity before namespace creation

Reviewed frozen production commit `47d18f4`.
No new actionable findings arose from these two hypotheses.
The runner passed 444 native assertions across both metadata layouts on arm64 and x86_64.
The host ran macOS 26.5.2 with Xcode 26.6.
Rosetta ran the Intel executable.

The runner compiled the complete frozen `NVBackupStore.m`.
Release metadata used the selected parent directly.
Development metadata supplied the selected parent and `directoryNamespace = "nvALT Development"`.
Every case began without a library directory or Development namespace.

## Hypothesis 1: an absent selected parent gets recreated

The probe captured the selected parent identity, then moved that disposable parent to a retained fixture path.
Publication, retention, and plaintext deletion each rejected the absent captured path with `ENOENT`.
None recreated the selected parent.
The checks ran before the first publication and after a successful publication.
All retained paths and file bytes remained unchanged, including the snapshot, manifest, ownership record, and lock file.

## Hypothesis 2: stale identity creates a namespace in a replacement parent

The probe created an empty replacement parent at the original path.
The replacement inode differed from the captured inode.
Publication, retention, and plaintext deletion each rejected the stale captured identity with `ESTALE`.
The replacement parent remained empty, with no namespace or library child.
The original retained parent still had identical paths and file bytes.

A retry with fresh captured metadata supplied the positive control.
The native store created the missing child directories and published an archive with exact byte readback.
The retained original snapshot files remained unchanged after that retry.
Both metadata layouts passed on both architectures.

These checks cover ordinary absent-path and stale-identity states at the store boundary.
They do not cover the controller's bookmark or canonicalization order, actual volume unmounts, or concurrent filesystem changes.
The probe did not construct a symlink or redirection fixture.
The archive contained disposable opaque bytes without application archive decoding.

The probe used Foundation without a GUI, preferences, keychain access, or Launch Services registration.
The runner recorded frozen source hashes and each subprocess result in `results.json`.
All source copies, executables, directories, and snapshots belonged to one disposable fixture tree.
The runner deleted that tree after completion.
No production files changed.

## Reproduction

Run from the repository root:

```sh
python3 -B Tests/DevelopmentBuildReview/round3/platform/run.py
```
