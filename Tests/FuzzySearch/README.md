# Fuzzy search validation

Run these checks from the repository root on macOS with full Xcode:

```sh
python3 Tests/FuzzySearch/Core/run.py
python3 Tests/FuzzySearch/run-service-tests.py
python3 Tests/FuzzySearch/Browser/run.py
python3 Tests/FuzzySearch/Persistence/run.py
python3 Tests/FuzzySearch/Highlights/run.py
```

Each runner accepts `--sanitize` and `--arch x86_64`.
The Core, service, Browser, and Persistence suites check production code with independent expectations or controlled dependencies.
The shared-source probe extracts the actual character-edit callback and sends notifications through real NSTextStorage.
It checks immediate invalidation in two observers before any model commit.

| Suite | Scope |
| --- | --- |
| Core | Full native order, typed terms, fallback, resumed scans, positions, cancellation, explicit limits, and allocation fault injection. |
| Service | Query parsing, immutable corpus updates, stale requests, independent owners, NFC mapping, source positions, errors, and worker lifetime. |
| Browser | Title-first groups, overlapping UUIDs, native order, row keys, unique command targets, retained rows, composition, excerpts, and captured inline edits. |
| Persistence | Mode and occurrence through bookmarks, saved searches, followed links, and legacy defaults. Negative mutations detect lost rows and changed legacy modes. |
| Highlights | Shared character edits invalidate source highlights without treating attribute changes as source mutations. |

After an Intel Development app build, run the production UI probe:

```sh
python3 Tests/FuzzySearch/UI/run.py
```

The probe uses a copied app, disposable notes, isolated defaults, and a shared desktop-test lock.
Its held-completion gate delays publication while retaining production matching and controller methods.
It covers Return during pending work, supersession, mutation, Reveal, restoration, closure, and duplicate-row editing.
`--build-only` compiles the probe without launching the app. Compilation does not establish UI behavior.

Run `python3 Tests/FuzzySearch/run-service-tests.py --benchmark` for generated-corpus measurements.
The fixture uses deterministic UUIDs with distributed bytes, since artificial shared-prefix keys distort Foundation dictionary timings.
The [service measurement record](Measurements/README.md) contains corpus sizes, query timings, cancellation timings, and memory use.
The service suite passes 135 checks natively and under ASan/UBSan.
The native bridge benchmark and dependency provenance are documented in [ORIGIN.md](../../Sources/Search/ORIGIN.md).

## Local validation limits

The Intel Development app builds on macOS 26.5.2 with Xcode 26.6 and deployment target 10.13.
Native arm64 tests and sanitizer runs pass for the implemented paths.
Intel process launches stall on this host both inside and outside the execution sandbox.
The full desktop suites were attempted but did not complete. The copied-app search probe has only been compiled here.
No production screenshot or desktop pass is claimed.

The initial 150 ms target for 10,000 notes totaling 50 MiB is not met.
Native scoring alone takes about 0.5–1.3 seconds on the measured arm64 corpus.
Queries remain asynchronous and results remain complete. Large individual native calls can delay cancellation.
Intel performance and complete UI publication require separate measurements.

The [source-highlight bound checks](HighlightBounds/FIX.md) cover cancellation, source compatibility, and the 2,048-range display limit.
