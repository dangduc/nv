# Org preview review, round 2: native correctness

This review uses a Linus Torvalds-inspired perspective on native boundaries, artifact checks, and straightforward failure handling.
It does not represent his views.

Reviewed snapshot: `415cf6920bd5c74bc3911829431f3dcff7c4acb2`.
The probe uses an immutable Git archive to avoid concurrent changes in the working directory.

## Result

No new actionable findings in this scope.
The first-round direct-Cargo finding is fixed.
The new native heading adapter passes the focused checks below.

The rebuild script derives the compiler's sysroot and supplies its runtime library directory before calling Cargo.
It rejects failed-strip warnings and checks the artifact's defined symbols before copying the output.
The manifest update follows a successful copy.

Relevant locations:

- `Scripts/rebuild-org-preview.py:39`: native symbol validation.
- `Scripts/rebuild-org-preview.py:79`: compiler runtime directory setup.
- `Scripts/rebuild-org-preview.py:89`: failed-strip rejection before artifact copy.
- `ThirdParty/OrgPreview/src/main.rs:27`: UTF-8 fragment encoding.
- `ThirdParty/OrgPreview/src/main.rs:88`: heading and explicit-ID resolution.

## New executable evidence

Run `python3 Tests/OrgPreviewReview/round2/torvalds/run.py` from the repository root.

All **68 checks passed**.
This round adds focused checks for the fixes instead of repeating the first-round dependency and notice audit.

The probe rebuilds the helper from a new directory with an empty Cargo cache.
It uses the installed Cargo executable directly and removes all caller-supplied `DYLD_` variables.
The production script supplies the runtime path itself.
There are no failed-strip warnings, and native symbol inspection confirms that the result is stripped.
The result matches the checked-in helper after masking only its 16-byte Mach-O UUID.

The probe also exercises rejection and copy failures:

| Case | Evidence | Result |
|---|---|---|
| Cargo returns zero with a strip warning | Simulated Cargo result; production script runs | Rejects before copy; output and manifest unchanged |
| Artifact retains defined symbols | Real compiled Intel executable; production inspector runs | Rejects before copy; output and manifest unchanged |
| Cargo returns an error | Simulated Cargo result; production script runs | Rejects before copy; output and manifest unchanged |
| Destination is read-only | Real filesystem copy failure | Returns an error; output and manifest unchanged |

The warning and compiler-error simulations replace only the Cargo build subprocess result.
The test still executes the production version check, sysroot lookup, validation ordering, and manifest handling.
A separate native C fixture checks actual symbol rejection.

Five new Org fixtures run 25 conversions across the checked-in and rebuilt helpers.
They cover UTF-8 headings and explicit IDs, aliases, duplicate IDs, later reserved IDs, and heading levels above six.
The Unicode fixture also uses LF, CRLF, and no final newline.

The rebuilt helper receives one-, two-, five-, and thirteen-byte pipe writes.
These writes split some multi-byte Unicode sequences.
All outputs match the reference for their source, and every link resolves to its expected generated anchor.
Heading start and end tags match, including the capped `h6` representation.
The conversions leave their disposable working directory unchanged.

## Artifact identity

The reviewed helper contains 366,408 bytes.
Its SHA-256 is `dc5c563e75589ed615bc9faaad465f093ba180ac9c1b6baa3c4b2d874123fcba`.
The independently rebuilt helper SHA-256 is `a2591ee6ec0e7e9c85448bb5ff01d35deb2ced06311cc190c88aa466bde8c534`.
Their only byte difference is the Mach-O UUID.

`metadata.json` records the adapter and rebuild-script hashes, toolchain, SDK, rejection results, and fixture output hashes.
`output.txt`, `rebuild-output.txt`, and `rebuild-log.txt` contain the execution results.

## Limits

The host is macOS 26.5.2 with Xcode 26.6, build `17F113`, and SDK 26.5.
The pinned compiler is Rust 1.98.1.
The native helper executes through Rosetta; actual macOS 10.13 execution remains untested.

The real copy failure happens before the destination opens.
This test does not establish atomic recovery from partial writes, disk exhaustion, or power loss.
The heading checks cover generated HTML and fragments; they do not prove WebKit scrolling or preview-controller state behavior.
The concurrent preview-controller change needs its separate review.
No production files were edited during this review.
