# Fuzzy search validation

Run these checks from the repository root on macOS with full Xcode:

```sh
python3 Tests/FuzzySearch/Core/run.py
python3 Tests/FuzzySearch/run-service-tests.py
python3 Tests/FuzzySearch/Browser/run.py
python3 Tests/FuzzySearch/Persistence/run.py
python3 Tests/FuzzySearch/Highlights/run.py
python3 Tests/FuzzySearch/HighlightBounds/run.py --negative-controls
python3 Tests/FuzzySearch/Lifecycle/run.py
python3 Tests/FuzzySearch/PositionMapping/run.py
```

Each runner accepts `--sanitize` and `--arch x86_64`.
The Core, service, Browser, and Persistence suites check production code with independent expectations or controlled dependencies.
The shared-source probe extracts the actual character-edit callback and sends notifications through real NSTextStorage.
It checks immediate invalidation in two observers before any model commit.

| Suite | Scope |
| --- | --- |
| Core | Full native order, typed terms, fallback, resumed scans, positions, cancellation, explicit limits, and allocation fault injection. |
| Service | Query parsing, line boundaries, native line ranking, repeated lines, Unicode offsets, corpus updates, stale requests, and independent owners. |
| Browser | Ranked line rows, repeated UUIDs, native order, row keys, unique command targets, retained rows, composition, excerpts, and captured inline edits. |
| Persistence | Mode and occurrence through bookmarks, saved searches, followed links, and legacy defaults. Negative mutations detect lost rows and changed legacy modes. |
| Highlights | Shared character edits invalidate source highlights without treating attribute changes as source mutations. |
| HighlightBounds | Bounded background discovery, exact source compatibility, stale-publication guards, and capped TextKit attributes. |
| Lifecycle | Main-thread callback disposal after completion, cancellation, replacement, and browser teardown. |
| PositionMapping | Independent Unicode range expectations and deterministic worker scheduling during long position mapping. |

After an Intel Development app build, run the production UI probe:

```sh
python3 Tests/FuzzySearch/UI/run.py --launch-services
```

The probe uses a copied app, disposable notes, isolated defaults, and a shared desktop-test lock.
Its held-completion gate delays publication while retaining production matching and controller methods.
It covers Return during pending work, supersession, mutation, Reveal, restoration, closure, and duplicate-row editing.
It also compares WindowServer pixels before and after a 120-row highlight pass without user interaction.
Run repeatable list-highlight fuzzing with an explicit seed and timeout:

```sh
NV_FUZZ_LIST_HIGHLIGHTS=1 NV_FUZZ_NATURAL=1 NV_FUZZ_SEED=3134984190 \
  NV_FUZZ_ITERATIONS=20 python3 Tests/FuzzySearch/UI/run.py --launch-services --timeout 240
```

Set `NV_FUZZ_DROP_REPAINTS=1` to verify that the compositor regression rejects missing repaint notifications.
`--build-only` compiles the probe without launching the app. Compilation does not establish UI behavior.

Run `python3 Tests/FuzzySearch/run-service-tests.py --benchmark` for generated-corpus measurements.
The fixture uses deterministic UUIDs with distributed bytes, since artificial shared-prefix keys distort Foundation dictionary timings.
The [service measurement record](Measurements/README.md) contains corpus sizes, query timings, cancellation timings, and memory use.
The line-candidate service suite passes 214 checks natively and under ASan/UBSan.
The native bridge benchmark and dependency provenance are documented in [ORIGIN.md](../../Sources/Search/ORIGIN.md).

## Line-candidate validation (September 19, 2026)

The Intel Development build succeeds on macOS 13.7.8 with Xcode 15.2.
The native service, browser, persistence, lifecycle, and position-mapping suites pass.
The service and browser suites also pass with ASan/UBSan.
The highlight-bound suite rejects its negative controls.
The foreground application probe passes 104 checks through Launch Services, including two optional screenshot checks.
The probe covers five matching lines from three notes, shared editing, Undo, restoration, highlights, and pending searches.
Long-note fixtures check that each selected body match enters the viewport, with highlighting enabled or disabled.
They also check stale scroll completions, saved viewport restoration, manual scrolling, selection across notes, and transitions from Preview to Source.
`NV_UI_ARTIFACTS` selects the screenshot directory.
Direct executable launch fails the foreground-focus check on this host.
After rebasing onto master `40dab8c`, the multiple-window suite passes 35 checks and 13 relaunch checks.
The earlier replacement-library stall was resolved by the library-switch fix on master.
The full regression suite stops at the direct-launch fuzzy UI focus check after rebase.
The same UI probe passes through Launch Services. Wrapped-separator checks also pass after rebase.
The scrolling follow-up regression run stopped at wrapped-separator note reattachment. That check passed on retry and on the unchanged build.
The backup application probe fails its encrypted-library restore check. The unchanged baseline build reproduces that failure.

## Historical validation limits (September 9, 2026)

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

All [18 review reports](Review/README.md) include executable evidence and their validation limits. Findings and delegated fixes are recorded on PR #10.
