# Native search bridge

`NVFZF.c` adapts `fzf-native` for nvALT and the standalone prototype.
The application submits typed literal terms. The prototype retains native fzf query syntax through separate entry points.
Both paths share the same scorer, rank keys, and native sorter.

The dependency comes from `dangduc/fzf-native` commit `4b9236e8cd1e9f9f3aaf5f2ebf83f1fc5995d38d`.
`ThirdParty/fzf-native/upstream.json` records the revision, SHA-256 hashes, and the local utf8proc correction.
The build compiles `fzf.c` and `utf8proc-2.10.0/utf8proc.c` directly.
The dependency contains no Emacs runtime, producer process, or platform binaries.

## Native extractions

`NativeRanking.inc` contains these unchanged sections from the upstream `fzf-native-module.c`:

- `FzfRankKeys` through `fzf_score_and_rank`, before `struct Candidate`.
- The `ScoredStr` declaration, before the immutable index-array implementation.
- `async_stop_requested` and `async_copy_bytes_abortable`.
- `cmp_scored_desc` through `counting_sort_scored_abortable`, before its synchronous wrapper.

The extraction retains native rank keys, stable radix order, and the heap-sort fallback for allocation failure.
The bridge preserves producer order during candidate compaction. Positive-term patterns receive one complete native sort after scoring.
Empty and inverse-only native queries retain producer order.

`NativePattern.inc` contains the unchanged `str_tolower` and `make_pattern_text` helpers from upstream `fzf.c`.
These helpers preserve native case conversion, decoded terms, and the SIMD query-plan layout.
The typed builder adds one positive AND set for each caller-supplied term. It never parses operator punctuation or escapes query text.
A Fuzzy term uses native v2 matching. An Exact term uses native contiguous matching.

The ranking extraction, bridge, and public header use `GPL-3.0-or-later`.
The pattern helpers and matcher retain their MIT notices. Unicode data retains the utf8proc notice.
The unchanged license texts are in `ThirdParty/fzf-native`.

## Ownership and limits

Each engine owns one default matcher slab. Calls on an engine are serial.
A job owns its copied terms and match buffer. Candidate arrays, candidate bytes, and cancellation tokens remain caller-owned until job destruction.
Jobs can move between serial engines between steps. Calls on the same job cannot overlap.
A step scores at most the requested candidate count. Finalization performs one native sort and transfers the complete result once.
Cancellation and errors publish no partial list.

Candidate NUL bytes remain searchable through explicit lengths. Terms reject embedded NUL bytes.
Typed terms must be nonempty and total at most 65,536 UTF-8 bytes. Zero terms return all candidates in producer order.
Candidate lengths cannot exceed `INT32_MAX` bytes. A collection cannot exceed `UINT32_MAX` entries.
These limits produce errors without truncation.

Both entry points ignore case, preserve accents, and use the default forward scoring scheme.
Canonical Unicode normalization belongs to the caller. There is no application title bonus, result cap, or second fuzzy sort.

Cancellation checks occur between candidates, inside native sorting, and during result copying.
A native scorer call remains uninterruptible. Batches bound candidate count, not elapsed time.
Unicode rank-length calculation and each selected-note position traversal also remain uninterruptible.

## Positions

The position adapter uses explicit candidate lengths, including candidate NUL bytes.
It checks membership with the bounded scorer, then invokes bounded algorithms for the parsed terms.
Each positive term receives a separate position buffer before the adapter joins the results.
This prevents UTF-8 greedy fallback from remapping positions from an earlier term.
Offsets are ascending, unique Unicode codepoint indexes. The caller maps them to its original UTF-16 text and composed-character ranges.

## Evidence

`Tests/FuzzySearch/Core/run.py` checks the vendored hashes, then compiles the bridge and an independent upstream synchronous reference.
`UpstreamReference.inc` retains the complete upstream section from `FzfRankKeys` to `struct Batch`.
This reference does not import the production ranking helpers.
The suite compares complete result order and score diagnostics. It also covers terms, positions, jobs, cancellation, and allocation failures.

On September 9, 2026, native arm64 and AddressSanitizer/UndefinedBehaviorSanitizer runs each passed 23,531 checks.
The Intel build compiled and linked with the macOS 10.13 target. Intel execution stalled in Rosetta startup before the harness printed output.
The prototype build and Swift checks passed against the shared bridge.

Clang analysis reported one possible uninitialized byte through the extracted lowercase helper and the upstream SIMD query-plan helper.
The reported path exits the lowercase loop after one byte, then treats the resulting string as at least three bytes long.
That path contradicts the loop bound and terminating NUL. Analysis of unchanged upstream `fzf.c` also reports lowercase/SIMD warnings.
The detailed logs remain under `build/FuzzySearchCoreTests/`.

Allocation injection covers bridge structures, typed terms, native sort scratch space, and a separate upstream matcher allocation domain.
Fresh-engine sweeps cover 94 search/position allocation ordinals and three slab allocation ordinals across 20 upstream sites.
These sites include parser storage, DP scratch arrays, retained and temporary UTF-8 maps, and position vectors.
Every encountered site receives a failure. Errors expose no partial output, and the same engine recovers on a subsequent call.
Optional shrink-allocation failures retain complete equivalent results. A later-batch OOM remains terminal and cannot publish earlier matches.
Removing the scorer OOM guard in a generated build makes the suite fail on an incomplete result.

This evidence covers the encountered paths, not every allocation in the dependency.
Unused position wrappers and the uncached normalized-pattern branch remain outside these sweeps.
The separately compiled utf8proc allocation API belongs to source preparation and has separate service tests.
Its size-only decomposition and recursive sequence expansion avoid adding offsets to NULL destination pointers.
These two local guards leave normalization output unchanged.

## Runtime measurements

[The native benchmark](../../Tests/FuzzySearch/Core/BENCHMARK.md) records the 10,000-note, 50.4 MiB experiment and prepared long-note cancellation.
Median C search time was 1,004.5 ms on an Apple M3. The 150 ms goal is unachieved.
Native scoring dominates this run. An extra 248 KiB of I32 scratch improved paired query medians by only 1.97%.
The implementation retains the native default capacities and complete native result order.
