# Native search performance evidence

The 150 ms search target is unachieved for this corpus.
The measurements identify native scoring as the dominant cost. The implementation retains the existing scorer, sorter, and slab capacities.

The run used an Apple M3 with 16 GiB RAM, macOS 26.5.2, Xcode 26.6, and native arm64 code.
Clang compiled the C sources at `-O2`. No Intel execution result is available.

## Corpus and method

The corpus contains 10,000 complete candidates totaling 52,826,668 bytes (about 50.4 MiB).
Each candidate contains a generated title, tags, and 5,243 source bytes separated by newlines.
The source repeats a fictional project-note sentence. This controlled corpus is not a sample of personal notes.
Its frequent matches measure dense scoring work and do not establish typical library latency.

The 12 queries are `road`, `copper`, `budget`, `deploy`, `finance`, `planning`, `source`, `weekly`, `archive`, `lantern`, `mtg`, and `review`.
Every query uses one typed fuzzy term. Each query runs three times for each configuration, giving 36 observations per configuration.
The paired order reverses in the middle round. The check compares every result index and score field for each pair.
All 36 pairs preserve complete native order and score diagnostics.

Preparation, scoring, and final sorting have separate timers. Candidate construction and UTF-8 preparation occur before measurement.
The benchmark excludes Cocoa title matching, browser publication, rendering, and source normalization.
The 95th percentile uses the nearest-rank observation. These small controlled samples are not production latency guarantees.

| Configuration | Median total | 95th percentile | Range |
| --- | ---: | ---: | ---: |
| Existing default slab | 1,004.5 ms | 1,355.0 ms | 529.8–1,367.1 ms |
| Experimental larger I32 scratch | 984.6 ms | 1,330.1 ms | 515.3–1,343.9 ms |

The existing slab has 2,048 I32 entries. The experiment uses 65,536 entries, adding 248 KiB per engine.
Both configurations retain the native 102,400-entry I16 limit, which controls the v2-to-v1 fallback.
The median improvement across paired per-query medians is 1.97%. The implementation does not adopt this small gain and extra memory.

For the existing slab, median scoring time is 1,004.4 ms. Median final sorting time is 0.067 ms.
A separate ASCII classification pass over the complete corpus takes 3.090 ms.
Caching that classification or changing final sorting cannot close the gap to 150 ms.

## Prepared long-note cancellation

The separate cancellation check uses one already prepared candidate and one native engine.
ASCII candidates contain `a`, `b`, and `c` at the start, middle, and end, with `x` elsewhere.
Unicode candidates contain repeated NFC `é` characters. Their query is `ééé`.
The controlling thread requests cancellation about 2 ms after the search thread starts.
Each case has three cancellation observations. Every cancelled call returns no result list.

| Candidate | Complete search | Cancellation release range |
| --- | ---: | ---: |
| 1 MiB ASCII with long gaps | 11.4 ms | 8.8–8.9 ms |
| 1 MiB dense Unicode | 8.9 ms | 6.2–6.9 ms |
| 8 MiB ASCII with long gaps | 90.6 ms | 87.6–87.8 ms |
| 8 MiB dense Unicode | 65.9 ms | 60.8–66.8 ms |

A single native scorer call remains uninterruptible. Cancellation returns after that call observes its next bridge check.
These cases meet 100 ms on this arm64 host. They do not establish a bound for arbitrary queries, positions, normalization, or Intel hardware.
Source-preparation measurements belong to the service benchmark.

## Reproduction

Run the paired scoring experiment:

```sh
python3 Tests/FuzzySearch/Core/run-benchmark.py
```

Run the prepared-candidate cancellation check:

```sh
python3 Tests/FuzzySearch/Core/run-benchmark.py --cancel
```

The recorded outputs are `build/FuzzySearchCoreTests/core-benchmark.csv` and `build/FuzzySearchCoreTests/cancellation-benchmark.csv`.
The experiment inspects the private engine slab only in its test translation unit. The application API and engine capacities remain unchanged.
