# Org preview review, round 1: native correctness and packaging

This review uses a Linus Torvalds-inspired perspective on native boundaries, dependency costs, and straightforward build behavior.
It does not represent his views.

Reviewed snapshot: `4467e7a7251ff3846c6d255db3bd64f465fda6b2`.
Base: `f3a8abb2b7942d06ec33af64b4946cfd1b6db163`.
The probe reads an immutable Git snapshot because another agent is fixing the helper's heading and link behavior.

## Finding

### P2: Prepare the direct toolchain runtime and reject failed stripping

Location: `Scripts/rebuild-org-preview.py:80`.
Related environment setup: `Scripts/rebuild-org-preview.py:67`.

The documented `--cargo` option accepts an absolute Cargo path.
With the pinned toolchain's direct Cargo executable, the rebuild produces an unstripped helper and reports success.
Cargo returns zero even though its `rust-objcopy` subprocess cannot load `@rpath/libLLVM.dylib`.
The script checks Cargo's exit code, architecture, deployment target, linked libraries, and a smoke conversion.
Those checks pass, so the script copies the larger artifact and can update its manifest.

The clean probe produced a 498,128-byte helper instead of the committed 353,912-byte helper.
The build log contains this diagnostic:

```text
warning: stripping debug info with `rust-objcopy` failed: signal: 6 (SIGABRT)
```

The adjacent loader diagnostic identifies the missing LLVM library.
This is a build-tool runtime problem; the generated helper runs normally and links only the system library.

The script should derive the pinned compiler's sysroot and include its `lib` directory in Cargo's runtime library path.
It should also reject failed-strip warnings before it copies an artifact or updates the manifest.
An absolute Cargo path should work consistently whether it names a rustup proxy or the installed toolchain executable.

A controlled experiment supports this fix.
I supplied the toolchain library directory inside the Python process before running the unchanged rebuild script.
The fresh offline rebuild then produced a 353,912-byte helper.
Every byte matched the committed helper after masking only its 16-byte Mach-O UUID.
No application source or helper source changed during this experiment.

The agent responsible for the helper has the finding and the controlled result.
This report does not claim that a production fix has already been validated.

## Executable evidence

Run these commands from the repository root:

```sh
python3 Tests/OrgPreviewReview/round1/torvalds/run.py
python3 Tests/OrgPreviewReview/round1/torvalds/run.py --toolchain-library-path
```

The default probe uses the immutable reviewed revision, a new source directory, and an empty Cargo cache.
The optional argument performs the controlled runtime-path experiment.
Pass `--cargo` and `--app` to select different local toolchain and built-application paths.

The native probe checks the actual resolved dependency graph, rather than counting vendored directories.
It verifies that all nine packages resolve within the staged sources: the helper and eight recorded dependencies.
Orgize has no enabled optional features. Indextree enables only `std`.
The sole build script is Jetscii's local macro generator and target-feature selector.
That script was inspected before the build.
No registry source, registry archive, registry index, or Git dependency content appeared in the empty Cargo cache.

The probe decodes Mach-O headers and load commands directly.
Both helpers are thin Intel executables with an exact macOS 10.13 deployment target and one system-library dependency.
The built application contains the reviewed helper byte for byte and retains its executable permission.
It also contains both complete notice resources.
Every dependency license listed in the manifest appears in the distribution notices.

Eleven ordinary fixtures cover headings, lists, literals, emphasis, tables, links, Unicode, newline conventions, and empty source.
Each fixture runs against the committed, rebuilt, and app-packaged helpers.
The rebuilt and packaged helpers also receive input through one-, seven-, and 4,096-byte pipe writes.
These writes split some Unicode sequences between calls.
All 77 conversions return matching output for their fixture and leave the disposable working directory unchanged.

| Run | Native checks | Rebuilt bytes | Comparison with committed helper |
|---|---:|---:|---|
| Direct Cargo, original script | 88 passed | 498,128 | Extra symbol data; stripping warning |
| Controlled toolchain runtime path | 89 passed | 353,912 | Only the Mach-O UUID differs |

The first run's passing checks concern packaging and conversion behavior.
They do not conceal the separate rebuild defect recorded in its size, log, and `only_uuid_differs` result.

## Recorded artifacts

The committed helper SHA-256 is `34d4469bb611c062a0730040ed1224228262e13d249b5437316947f433fe4359`.
The controlled rebuilt helper SHA-256 is `b9811a7b281ce498b2de24dade8a7736cc359d483504d8ee4bcbc4a014379876`.
Its only differing range is the UUID at byte offset 1,792, with length 16.

- `run.py`: independent native and transport probe.
- `unconfigured-output.txt`, `unconfigured-metadata.json`, and `unconfigured-rebuild-log.txt`: original-script result.
- `output.txt`, `metadata.json`, and `rebuild-log.txt`: controlled runtime-path result.
- `rebuild-output.txt` and `unconfigured-rebuild-output.txt`: script output for each run.

## Limits

The native checks run through Rosetta on macOS 26.5.2 with Xcode 26.6, build `17F113`.
The compiler is Rust 1.98.1, and the SDK is 26.5.
The deployment target does not prove execution on an actual macOS 10.13 system.
These checks do not exercise WebKit, sanitization, window routing, or all Org export semantics.
They use ordinary bounded inputs and do not reproduce parser vulnerabilities.
The concurrent heading and link fix needs its own subsequent validation.
