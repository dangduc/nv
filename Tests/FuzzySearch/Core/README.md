# Native fuzzy search checks

From the repository directory, run the suite:

```sh
python3 Tests/FuzzySearch/Core/run.py
python3 Tests/FuzzySearch/Core/run.py --sanitize
```

Compile and link the shipping architecture without execution:

```sh
python3 Tests/FuzzySearch/Core/run.py --arch x86_64 --compile-only
```

The suite uses vendored sources and needs no network access or Emacs installation.
It writes objects and executables under `build/FuzzySearchCoreTests/`.
A 180-second timeout applies to each command. Intel execution requires a working Rosetta installation on Apple Silicon.

The reference contains unchanged upstream synchronous ranking code. It does not import production bridge helpers.
Comparisons include every result index, public score, rank score, and trimmed-length key.
The corpus has 432 candidates. Native syntax checks cover 33 queries in both native modes.
Typed terms also compare against representable native queries. Separate fixtures assert literal operator and whitespace behavior.

Resumable jobs use batches of 1, 7, 255, and all candidates.
The suite checks phrase contiguity, Unicode case conversion, copied terms, cancellation between batches, and single result transfer.
Additional checks cover candidate NUL bytes, Unicode positions, greedy fallback, saturated rank keys, and allocation failures.
No test treats a cancelled partial scan as a complete empty result.

Separate allocation hooks cover bridge structures and the upstream parser, scorer, position vectors, UTF-8 maps, and slab storage.
Fresh-engine sweeps inject 97 allocation ordinals across 20 upstream sites. Failures cannot publish partial results or positions.
The same engine must recover after each fault. Optional allocation fallbacks must preserve complete result order and positions.
Unused position-wrapper and uncached normalized-pattern allocations remain outside the sweeps. Source normalization has separate service tests.

This negative check must fail:

```sh
python3 Tests/FuzzySearch/Core/run.py --mutation ignore-scorer-oom
```

The mutation removes the scorer error guard from a generated build copy. The sweep then detects an incomplete result.
The sanitizer run enables AddressSanitizer and UndefinedBehaviorSanitizer.

[The benchmark record](BENCHMARK.md) contains runtime measurements, inputs, and reproduction commands.
