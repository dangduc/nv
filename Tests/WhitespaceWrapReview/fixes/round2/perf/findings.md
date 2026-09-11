# Round 2 P3 attribution: many-paragraph resize cost

The glyph adjustment accounts for a repeatable resize increment in this fixture.
The shared character-wrap paragraph policy remains enabled in both control modes.
These measurements support a local glyph-callback optimization before the next review round.
They do not establish that the remaining native resize path is fast.

## Controlled comparison

Both modes run the same frozen `072a6bc` Development app.
Its executable SHA-256 is `be02dd1fe33a39c74b8961441be55f4f91378d46935bdba99fd610d405c3e09b`.
The glyph-on observer forwards the actual production glyph delegate unchanged.
The glyph-off control returns zero only from `shouldGenerateGlyphs`, which lets AppKit keep native elastic-space properties.
All other production behavior and the immutable character-wrap style remain active.

The fixture repeats `alpha\tbeta   Việt 👩🏽‍💻 中文   \n` 1,024 times, then adds 200 spaces.
Its initial length is 32,968 UTF-16 units, with Plain Text syntax and Menlo 12.
Each trial sends 64 native key events and makes eight synchronous visible-window resize requests.
The text container alternates between 504 and 844 points.
The body and launch helpers derive from the round-two Luu probe, restricted to this one fixture.
The new observer supplies the independent glyph control and callback timing.

| Median across six trials | Glyph adjustment on | Glyph adjustment off |
| --- | ---: | ---: |
| Eight visible resize requests | 2,877.50 ms | 2,617.90 ms |
| Main-thread CPU | 3,190.23 ms | 2,926.84 ms |
| Dispatch for 64 keys | 203.22 ms | 210.42 ms |
| Observed glyph-callback time | 542.62 ms | 40.63 ms |
| Glyph callbacks | 4,113,186 | 4,113,186 |

The median resize increment is 9.92%.
The first app order reports 2,886.50 versus 2,617.50 ms.
The reversed order reports 2,863.74 versus 2,618.30 ms.
Each order contains three trials per mode.
All four app runs pass 415 checks each, including exact source, committed model, and caret preservation.
Both modes reuse one immutable paragraph-style object.

The glyph-off control disables the requested space behavior. It is an attribution control, not a proposed production correction.
The experiment changes glyph properties as well as callback execution.
It does not isolate callback arithmetic from the downstream layout cost of those properties.

## Callback shape

A separate one-trial sample records batch sizes and nonzero production returns.
It completes 141 checks, including the final evidence-write check.

| Observation | Count |
| --- | ---: |
| Glyph callbacks | 4,110,226 |
| Changed batches | 2,063,382 |
| Single-glyph batches | 1,023,422 |
| Total glyph units supplied | 33,001,272 |
| Largest batch | 268 glyphs |

The reviewed method allocates and frees a property array for each changed batch.
This sample therefore performs about 2.06 million such allocation/free pairs.
The method also obtains storage, source string, and source length before it checks for an eligible elastic glyph.

The measurements support two bounded corrections:

- Return before source queries when a batch contains no eligible elastic glyph.
- Use a small stack property buffer for common batches, with the existing allocation path for larger batches.

Those changes preserve glyph IDs, indexes, source characters, and final layout properties.
A production comparison must establish their actual effect before the P3 finding is closed.
This report records attribution evidence only. It does not claim a completed performance correction.

## Reproduce

The retained pre-optimization app is `build/WhitespaceWrapReview/fixes/round2/perf/Unoptimized.app`.
The runners accept `--app` to select another copy with the same verified executable.
From the worktree, run:

```sh
python3 Tests/WhitespaceWrapReview/fixes/round2/perf/run.py
python3 Tests/WhitespaceWrapReview/fixes/round2/perf/run.py --without-first
python3 Tests/WhitespaceWrapReview/fixes/round2/perf/sample-batches.py
```

The runner holds the common GUI lock and uses isolated app copies, notes, preferences, and support paths.
The committed result files contain both execution orders and the batch sample.
Full logs and generated products remain in `build/WhitespaceWrapReview/fixes/round2/perf/`.

## Limits

Host: macOS 26.5.2 (25F84), Intel app under Rosetta.
The timers measure synchronous requests, not physical live-resize tracking or every displayed frame.
The callback timer includes callbacks outside the resize phase and after final complete-layout collection.
It cannot be subtracted directly from the resize total.
The observer adds a counter and two clock reads to each callback in both modes.
The batch-size sample adds further diagnostic counters and does not enter the six-trial medians.
These results do not establish macOS 13 performance or explain the full baseline latency.

The final production comparison is in [correction.md](correction.md).
