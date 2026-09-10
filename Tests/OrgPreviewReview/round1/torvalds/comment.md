### Round 1 — native correctness and packaging

Linus Torvalds-inspired review perspective; this does not represent his views.
Reviewed immutable snapshot `4467e7a7251ff3846c6d255db3bd64f465fda6b2` against `f3a8abb2b7942d06ec33af64b4946cfd1b6db163`.

**P2 — Prepare the direct toolchain runtime and reject failed stripping** (`Scripts/rebuild-org-preview.py:80`, environment setup at line 67). The documented `--cargo` option accepts the pinned toolchain's direct Cargo executable. In that configuration, `rust-objcopy` cannot load `@rpath/libLLVM.dylib`, but Cargo reports success with a warning. The script then copies a 498,128-byte unstripped helper and can update the manifest, instead of producing the committed 353,912-byte artifact. Include the pinned sysroot's library directory in the build environment and reject failed-strip warnings before artifact copy or manifest update.

I wrote a clean-snapshot, empty-cache rebuild probe. Supplying that runtime directory inside the Python process produced a helper identical to the committed artifact except its 16-byte Mach-O UUID. The helper agent has this finding and controlled evidence.

The remaining checks passed: eight resolved source dependencies, disabled optional Orgize/macro features, one system dynamic library, exact macOS 10.13 target, app helper bytes and executable permission, and complete notice resources. Eleven ordinary fixtures produced matching output across 77 conversions, including byte-sized pipe writes that split Unicode sequences. The original invocation passed 88 packaging/transport checks; the controlled run passed 89, including normalized artifact equality.

Actual execution on macOS 10.13 remains untested. This review does not cover WebKit or the concurrent heading/link fix. Evidence and reproduction: `Tests/OrgPreviewReview/round1/torvalds/report.md` and `run.py`.
