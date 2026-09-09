# Fuzzy search review record

PR: [native fuzzy search with title-first rows](https://github.com/fastducduc/nv/pull/10).

All three requested review rounds are complete, with six perspectives per round.
All actionable findings were assigned to implementation agents and fixed. The final round found no new actionable defects.
The named perspectives guide independent subagents; the named people did not perform or endorse these reviews.
Each reviewer writes executable evidence and records its scope and limits. Implementation agents address confirmed findings.

## Round 1

Reviewed production implementation: `c7e61cb`.

| Perspective | Evidence | Finding and status |
| --- | --- | --- |
| John Ousterhout: ownership and interfaces | [Report](round-1/ousterhout/findings.md) | No actionable finding in scope; 83 native and 83 sanitizer checks. [PR comment](https://github.com/fastducduc/nv/pull/10#issuecomment-5599706122). |
| Dan Luu: measured performance | [Report](round-1/luu/findings.md) | P2: synchronous literal source highlights block input on large notes. Fixed: worker discovery and a 2,048-range display limit; 106 checks and six negative controls. [PR comment](https://github.com/fastducduc/nv/pull/10#issuecomment-5599763681). |
| Linus Torvalds: C correctness and simplicity | [Report](round-1/torvalds/findings.md) | No actionable finding in scope; 431,292 independent sanitizer assertions. [PR comment](https://github.com/fastducduc/nv/pull/10#issuecomment-5599710651). |
| Kyle Kingsbury: asynchronous state | [Report](round-1/kingsbury/findings.md) | Two P2s: focus loss preserves Return intent; background plural Reveal omits targets. Fixed; native and sanitizer regression checks pass. [PR comment](https://github.com/fastducduc/nv/pull/10#issuecomment-5599877216). |
| Contrarian: interaction assumptions | [Report](round-1/contrarian-ui/findings.md) | P2 public-method robustness: overlapping inline editors replace the prior target too soon. Ordinary app reachability is unproven. Guard fixed; 102 native and sanitizer checks pass. [PR comment](https://github.com/fastducduc/nv/pull/10#issuecomment-5599878262). |
| Contrarian: compatibility assumptions | [Report](round-1/contrarian-compat/findings.md) | Two P2s: present-empty legacy search restores Fuzzy; Tab changes Fuzzy to Exact. Fixed; native and sanitizer regression checks pass. [PR comment](https://github.com/fastducduc/nv/pull/10#issuecomment-5600029967). |

Round 1 fixes are complete.

## Round 2

The reports identify the repaired source with file and method hashes.

| Perspective | Evidence | Finding and status |
| --- | --- | --- |
| John Ousterhout: cancellation ownership | [Report](round-2/ousterhout/findings.md) | P2: queued canceled work can release the browser session on the worker. Fixed; 236 native and sanitizer lifecycle checks pass. [PR comment](https://github.com/fastducduc/nv/pull/10#issuecomment-5600257714). |
| Dan Luu: shared-worker responsiveness | [Report](round-2/luu/findings.md) | P2: long position mapping delays another browser query. Fixed with resumable mapping; independent Unicode and scheduling checks pass. [PR comment](https://github.com/fastducduc/nv/pull/10#issuecomment-5600400103). |
| Linus Torvalds: Unicode and display boundaries | [Report](round-2/torvalds/findings.md) | No actionable finding; 40,171 native and sanitizer assertions. [PR comment](https://github.com/fastducduc/nv/pull/10#issuecomment-5600291250). |
| Kyle Kingsbury: intent ordering | [Report](round-2/kingsbury/findings.md) | P2: older restoration strands newer Reveal. Fixed; 78 native and sanitizer checks pass. [PR comment](https://github.com/fastducduc/nv/pull/10#issuecomment-5600211154). |
| Contrarian: duplicate-row interactions | [Report](round-2/contrarian-ui/findings.md) | No new actionable finding; 71 native and sanitizer checks. [PR comment](https://github.com/fastducduc/nv/pull/10#issuecomment-5600211333). |
| Contrarian: compatibility and restoration | [Report](round-2/contrarian-compat/findings.md) | No actionable finding; 279 native and sanitizer assertions. [PR comment](https://github.com/fastducduc/nv/pull/10#issuecomment-5600366739). |

All six second-round reviews and their fixes are complete.

## Round 3

Reviewed production code: `11f571f`. Later commits contain review records and documentation.

| Perspective | Evidence | Finding and status |
| --- | --- | --- |
| John Ousterhout: callback ownership | [Report](round-3/ousterhout/findings.md) | No actionable finding; 144 native and sanitizer checks. [PR comment](https://github.com/fastducduc/nv/pull/10#issuecomment-5600658540). |
| Dan Luu: repeated peer scheduling | [Report](round-3/luu/findings.md) | No actionable finding; 82 native and sanitizer checks, no-yield control rejected. [PR comment](https://github.com/fastducduc/nv/pull/10#issuecomment-5600766630). |
| Linus Torvalds: mapping boundaries and output ownership | [Report](round-3/torvalds/findings.md) | No actionable finding; 93 native and sanitizer checks. [PR comment](https://github.com/fastducduc/nv/pull/10#issuecomment-5600766806). |
| Kyle Kingsbury: interleaved selection histories | [Report](round-3/kingsbury/findings.md) | No actionable finding; 44 native and sanitizer assertions across four new histories. [PR comment](https://github.com/fastducduc/nv/pull/10#issuecomment-5600658833). |
| Contrarian: delayed tag actions and same-note occurrences | [Report](round-3/contrarian-ui/findings.md) | No actionable finding; 89 native and sanitizer checks, three negative controls rejected. [PR comment](https://github.com/fastducduc/nv/pull/10#issuecomment-5600572748). |
| Contrarian: independent legacy Exact comparison | [Report](round-3/contrarian-compat/findings.md) | No actionable finding; 1,397 native and sanitizer assertions against the pre-PR session. [PR comment](https://github.com/fastducduc/nv/pull/10#issuecomment-5600766960). |

The maintained lifecycle, bounded-highlight, and position-mapping suites run in Intel CI.
The original review records remain available beside separate repair evidence. Reports state where fixtures replace full-app behavior.

## Validation limits

[Intel CI passed](https://github.com/fastducduc/nv/actions/runs/34341896868) at `a9636d6`, including all maintained search suites, the app build, and archive checks.
That run includes the complete production repairs reviewed in round three.
Local builds use macOS 26.5.2 and Xcode 26.6; local native probes use arm64.
The copied Intel app cannot start on this host. Full desktop validation and a production UI screenshot remain unavailable.
Native or extracted-method fixtures do not establish full desktop behavior.

The 150 ms warm-search target remains unmet for the generated 10,000-note, 50 MiB corpus.
See [service measurements](../Measurements/README.md) and [native measurements](../Core/BENCHMARK.md).

The 20,000-row publication fixture also exceeds the initial 8 ms target.
Individual native calls and unusually long composed sequences can exceed the worker time target.
See the [position-mapping record](../PositionMapping/README.md) for measured improvements and remaining limits.
