# Round 2 P3 correction: reduce glyph-callback allocation

The optimization reduces resize work and removes nearly all recorded `malloc` calls during the glyph callback in the tested fixture.
It preserves the source, caret, shared paragraph policy, and final line count.
The P3 finding is mitigated, not fully resolved.
The remaining measured cost is an accepted limit of the current public glyph customization.

The production correction returns before source queries for batches without an eligible elastic glyph.
Eligible batches use a 64-property stack buffer, with a heap fallback for larger batches.
Both compared apps keep the complete production glyph adjustment enabled.

## Exact production comparison

`compare-optimized.py` runs the same body and observer as the attribution experiment.
It changes only the app selection and expected binary identities.
Each order contains three trials per app, for six trials per build.
The reversed order also shows lower resize work after the optimization.

| Median across six trials | Before | Optimized |
| --- | ---: | ---: |
| Eight visible resize requests | 2,851.93 ms | 2,720.88 ms |
| Main-thread CPU | 3,164.45 ms | 3,026.34 ms |
| Dispatch for 64 keys | 225.54 ms | 219.40 ms |
| Observed glyph-callback time | 535.09 ms | 454.49 ms |
| Glyph callbacks | 4,113,186 | 4,113,186 |
| Final complete-layout lines | 1,027 | 1,027 |

The median resize reduction is 4.60%.
The callback counts and final geometry remain equal.
All four app runs pass 415 checks each.
Those checks cover exact live source, committed note source, caret position, and paragraph-style identity.
The fixture and synchronous resize operations remain identical to the initial attribution experiment.

Before binary SHA-256: `be02dd1fe33a39c74b8961441be55f4f91378d46935bdba99fd610d405c3e09b`.
Optimized binary SHA-256: `55f97d1af69d120f385698b428a616e473be020200d3fe0ebcc6b626253459be`.

## Direct allocation sample

A separate one-trial comparison interposes `malloc` and `free` in each disposable app.
A thread-local counter limits recording to execution inside the real production glyph method.
The interposition functions forward allocation and deallocation normally.
No allocation results or glyph results change.

| Calls during the real glyph method | Before | Optimized |
| --- | ---: | ---: |
| `malloc` | 2,064,738 | 1,161 |
| `free` | 2,066,717 | 3,129 |

The recorded `malloc` reduction is 99.944%.
These are measured allocator calls, not counts inferred only from batch sizes.
The scope also includes AppKit work called by `setGlyphs`, so it does not identify every individual property-buffer allocation.
The counters cover `malloc` and `free`. They do not measure `calloc`, `realloc`, or direct zone allocation calls.
The old-app sample supplies a positive control for the interposition: it observes the expected millions of allocations.
Both allocation-sample runs pass 141 checks and retain 1,027 final lines.

The allocation sample adds allocator instrumentation across the process.
Its timings are excluded from the six-trial performance medians.

## Remaining cost and disposition

The earlier glyph-off diagnostic reported a 2,617.90 ms resize median with the same character-wrap paragraph policy.
The optimized app's 2,720.88 ms median remains approximately 3.93% higher.
Those measurements come from separate phases, so that difference is context rather than a new simultaneous comparison.
The original native baseline also differs from the chosen paragraph policy.

The correction removes the identified allocation hotspot and reduces the measured P3 increment.
It does not establish that all residual glyph work is free or that the large-note resize path is responsive.
Further changes need separate attribution of the remaining callback and AppKit work.
The disposition retains this correction and documents the remaining cost for large notes with many mixed-script paragraphs.

## Reproduce

From the worktree, run:

```sh
python3 Tests/WhitespaceWrapReview/fixes/round2/perf/compare-optimized.py
python3 Tests/WhitespaceWrapReview/fixes/round2/perf/compare-optimized.py --after-first
python3 Tests/WhitespaceWrapReview/fixes/round2/perf/count-allocations.py
```

The runners accept `--before-app` and `--after-app` overrides and check both executable hashes.
The default old app is the retained `Unoptimized.app` in the ignored output directory.
The default optimized app is the current Development build.

Both timing orders, the allocation sample, and compact medians are committed beside this report.
Complete logs and generated products remain in `build/WhitespaceWrapReview/fixes/round2/perf/`.

Host: macOS 26.5.2 (25F84), Intel apps under Rosetta.
The timers do not measure every painted frame, physical live-resize tracking, or macOS 13 behavior.
The glyph timer also includes callbacks after the timed resize phase during complete-layout collection.
It cannot be subtracted directly from the resize total.
