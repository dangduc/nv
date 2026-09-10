This probe verifies the fix for the round-one quadratic link-publication finding.

Run from the worktree root:

```sh
python3 Tests/TypingReview/fixes/link-publication/run.py
```

The runner compiles the production source-analysis helper and link methods.
It extracts the exact current `sourceAnalysis:didFinish:` method into a fixture session.
Generated source and the executable stay under `build/TypingReview/fixes/link-publication`.
The round-one evidence stays unchanged.

All 11 semantic cases passed: unchanged runs, changed targets, overlap across two old runs, shifted runs, merged and split runs, insertion and removal between preserved runs, and empty transitions.
Each case verifies the complete final link ranges, original source, and unrelated attributes.
Unchanged and repeated publication must emit no storage-edit notifications.
The overlap case detects additions erased by a later removal.

The patch merges old and new ordered runs with two indices.
It collects changed runs, applies all removals, then applies all additions.
The comparison no longer depends on dictionary hashes.

The final saved run passed without compiler warnings on macOS 26.5.2, using x86_64 under Rosetta and Apple clang 21 with `-O2`.
The values below measure publication after an actual edit in the final plain-text line.

| Fixture | Links | Round-one publication | Fixed publication |
| --- | ---: | ---: | ---: |
| Wiki / 12.5 KB | 500 | 45.466 ms | 0.311 ms |
| Wiki / 25 KB | 1,000 | 182.696 ms | 0.644 ms |
| Wiki / 50 KB | 2,000 | 719.788 ms | 1.259 ms |
| Wiki / 100 KB | 4,000 | 2,848.058 ms | 5.901 ms |
| Web URLs / 88 KB | 2,000 | 715.369 ms | 3.703 ms |

The unchanged 4,000-link publication falls from about 2.85 seconds to about 6 ms.
Its initial link publication takes 7.536 ms, compared with 719.019 ms in round one.
These are isolated method timings without layout managers or drawing, not frame-time measurements.
The whole publication includes Cocoa enumeration, allocation, and storage work beyond the linear comparison.
Other build and review activity was running on the host; small timing differences are not treated as regressions.

`output.txt` contains the final run.
`environment.json` records the command, host, HEAD, and SHA-256 of the modified production source.
The HEAD value alone does not identify uncommitted changes.
`git diff --check -- Sources/Editor/NVNoteEditingSession.m` also passed.
