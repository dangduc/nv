# Direct Cargo rebuild fix

The rebuild script now supplies the pinned toolchain library path for rust-objcopy.
It rejects stripping warnings before replacing the artifact, even when Cargo exits successfully.
Artifact inspection also rejects remaining defined symbols, which detects cached unstripped output.

A clean build from an isolated source copy succeeds with the direct Cargo path and no inherited DYLD_LIBRARY_PATH.
The result is 366,408 bytes. Its contents match the frozen helper except for the 16-byte Mach-O UUID.
[direct-cargo-comparison.json](direct-cargo-comparison.json) records both hashes and the comparison.
The native inspection verified x86_64, the macOS 10.13 deployment command, system-library linkage, stripped symbols, and heading output.

The maintained `Tests/Regression/org-preview/rebuild-tests.py` adds two executable regression probes:

- Cargo exits successfully with a strip warning. The rebuild fails and preserves the existing artifact and manifest.
- A native unstripped fixture reaches artifact inspection. Inspection rejects it before native conversion.

Both probes pass. The complete helper suite also passes its 45 formatting, link, and boundary checks.
The original round-one rebuild results remain unchanged in the parent directory.
