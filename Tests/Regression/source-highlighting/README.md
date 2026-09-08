# Source highlighting checks

From the repository root, run:

```sh
python3 Tests/Regression/source-highlighting/run.py
```

The harness compiles the vendored C runtime, four generated grammars, required scanners, and Objective-C adapter.
It targets Intel and macOS 10.13. Apple Silicon requires Rosetta.
The harness uses Foundation and TextKit without an application window or user notes.

The checks cover:

- JSON, HTML, and Markdown semantic captures.
- UTF-16 offsets for surrogate pairs, combining marks, and CRLF line endings.
- Equivalent incremental and fresh results after character replacements, incomplete syntax, and Markdown block changes.
- Separate Markdown block and inline parsing, without fenced-language injection.
- Plain Text and Textile fallback, size limits, cancellation, and rejected query predicates.
- Shared analysis across two layout managers, with separate search backgrounds.
- Display attributes that do not change shared text or persisted attributes.
- Character generations, attribute-only changes, stale results, syntax changes, and closure.
- Fully laid-out source after Undo-style shortening, Redo-style insertion, and whole-document deletion.
- Actual capture-write counts across four and twenty layouts, including plain fallback and recovery when layouts detach.

The source adapter copies immutable snapshots on the main thread.
One serial worker owns the parser state for each observed editing session.
Only one request per analysis object can run or wait for a main-thread result.
The latest character generation supersedes an older request.
The final detached layout releases its analysis object and parser state.

Character notifications invalidate a shared revision token before TextKit updates its glyph caches.
The editor immediately ignores captures from that revision.
Temporary attribute removal waits until the next event-loop turn, after TextKit processes the changed ranges.
The regression fixture rejects synchronous capture removal during character processing.

The initial limits are 524,288 UTF-16 units, 30,000 captures, 4,096 concurrent query matches, and a 120ms worker budget.
The parser checks cancellation during parsing, query execution, and Markdown inline-range traversal.
Plain source remains editable when a limit stops analysis.
The worker budget does not include TextKit display updates.
A separate display limit permits at most 4,096 capture writes across all attached layouts for one revision.
Results above this limit display plain source in every layout.
Removing extra layouts can restore highlighting from the retained result.
The limit bounds capture writes, not glyph layout, painting, or end-to-end typing latency.

The harness reports parser timing and peak process memory.
On macOS 26.5.2 with Xcode 26.6, the September 8 run passed 345 checks.
For 8,000 Markdown UTF-16 units, median parsing took 10.3ms and the maximum took 13.9ms.
For 120,000 units, all ten requests reached the work limit and returned plain fallback in approximately 123ms.
The harness reached 38.1MiB peak resident memory.
These measurements exclude browser layout, painting, and end-to-end typing latency.

Application validation also requires desktop checks for editor commands, Undo, composition, window presentation, and source colors.
