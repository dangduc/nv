# NV Search Prototype

This standalone macOS app explores fuzzy search over complete notes with the current `fzf-native` source.
It does not link nvALT or open its library. All edits remain in the prototype's memory.

The `main` branch was downloaded on September 9, 2026, at commit `4b9236e8cd1e9f9f3aaf5f2ebf83f1fc5995d38d`.
The minimal source subset is in `ThirdParty/fzf-native`. The prototype shares its C bridge with `Sources/Search`.
The C adapter preserves upstream ordering. It adds no title bonus or second application sort.

From the repository directory, build and open the app:

```sh
python3 Prototypes/FuzzySearch/run.py
```

The output is `build/FuzzySearchPrototype/NV Search Prototype.app`.
The runner compiles for the host architecture and applies an ad hoc signature.
This experiment requires macOS 12 or later and Xcode. Apple Silicon runs it natively.

The runner checks the dependency revision. A later upstream revision requires another extraction and ordering comparison before use.
The app bundles the required GPL, MIT, and Unicode notices in `Contents/Resources/Licenses`.
`Core/ORIGIN.md` records the extracted native code and its license boundaries.

The window starts with 40 fictional notes. The corpus menu also offers 1,000 or 10,000 generated notes.
Generated notes repeat the sample scenarios with distinct titles and IDs. Their results do not establish real-library ranking quality.
The source editor is below the notes list, as in nvALT.
Typing changes the source in memory and refreshes the current search.
Reset Samples discards those temporary changes.

Load Notes Folder reads supported UTF-8 files recursively.
It accepts plain text, Markdown, Textile, HTML, JSON, YAML, TOML, XML, CSV, and log files.
It skips hidden files, packages, symbolic-link files, unsupported encodings, and files larger than 16 MiB.
An import accepts at most 20,000 files and 128 MiB. The status includes the skipped-file count.
It does not read nvALT archives or write imported files.

Both prototype search modes use **native fzf query syntax**. The nvALT interface uses separate typed literal terms.

| Control or query | Behavior |
| --- | --- |
| Fuzzy | Terms use ordered character matching with gaps. |
| Exact terms | Terms use contiguous matching by default. Native operators still apply, including the apostrophe toggle. |
| `copper lantern` | Both terms must match the same complete note. |
| `'cafe` | In Fuzzy mode, require a contiguous `cafe` match. |
| `!archive` | Exclude a matching term. |
| `^Meeting` | Match the start of the combined candidate. |
| `cafe \| café` | Match either term. Enter a plain `|` character in the search field. |

The candidate is the title, a newline, tags, a newline, and complete source text.
Fuzzy terms can span lines or field separators. Cases such as `qzr` make this visible.
The engine ignores case, preserves accents, and uses its default score scheme and forward direction.
The prototype normalizes candidate and query copies to NFC and maps source highlights back to the original text.
Only the selected note receives detailed highlight positions. List excerpts currently show the start of each body.

The table shows the native rank score. Hover over a score for the public score and trimmed-length key.
The engine can clamp scores and lengths. Its default slab can use greedy matching on long inputs.
The prototype preserves those behaviors so the experiment can expose them.
The status separates native search time, corpus preparation time, and total response time.

Useful first queries are `nebula42`, `juniper`, `qzr`, `silverfin`, `requestID`, `café`, `鴨川`, and `cobaltquartz`.
`Fixtures/scenarios.md` explains the relevant notes and comparisons.
Arrow keys move through results from the search field. Return focuses the selected source after the current search completes.
Escape clears the query. Command-F focuses search.
The prototype does not create or save notes on Return.

The experiment uses one serial search worker and a reusable native slab.
New queries cancel obsolete work. The source snapshots are immutable during a search.
Corpus preparation currently rebuilds after an edit. The production plan's per-note cache and two-worker scheduler remain future work.
One large-note matcher call remains uninterruptible, even though result sorting supports cancellation.

Build without opening a window:

```sh
python3 Prototypes/FuzzySearch/run.py --build-only
```

Run the native and Swift checks:

```sh
python3 Prototypes/FuzzySearch/run.py --check
python3 Prototypes/FuzzySearch/Core/Tests/run.py --sanitize
```

Run the disposable UI smoke check from an active desktop:

```sh
python3 Prototypes/FuzzySearch/run.py --ui-smoke
```

The native checks compare 432 candidates and 33 queries in both modes with a separately extracted upstream reference.
They cover ordering, score diagnostics, Unicode positions, candidate NUL bytes, cancellation, and bridge and upstream allocation failures.
The Swift checks cover original UTF-16 ranges after Unicode normalization and candidate field offsets.
The UI smoke check opens its own window and exits after its assertions. It does not use a personal notes library.

Validated on September 9, 2026, with macOS 26.5.2, Xcode 26.6, and a native arm64 build.
The original native and sanitizer runs each passed 14,992 checks. Swift mapping checks and the original bridge analysis also passed.
After promotion, the shared native and sanitizer suites each passed 23,531 checks. The build and Swift checks also passed.
[The bridge record](../../Sources/Search/ORIGIN.md) documents the current analysis warning and Intel execution limit.
The desktop smoke passed layout, superseded queries, source edits, stale-result protection, corpus replacement, and zero-result checks.
Visual checks confirmed the notes list above the source editor and the selected source's match highlights.
The sample query `qzr` returned five notes in Fuzzy mode and one in Exact terms mode.
Both generated corpus controls worked. One warm `qzr` query took 17.5 ms with 1,000 notes and 164.9 ms with 10,000 notes.
Those response times are individual observations from generated data. They do not establish production latency percentiles or ranking quality.
