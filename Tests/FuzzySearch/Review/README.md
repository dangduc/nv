# Fuzzy search review record

PR: [native fuzzy search with title-first rows](https://github.com/fastducduc/nv/pull/10).

The requested review has three rounds with six perspectives per round.
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
| John Ousterhout: cancellation ownership | [Report](round-2/ousterhout/findings.md) | P2: queued canceled work can release the browser session on the worker. Fix delegated. [PR comment](https://github.com/fastducduc/nv/pull/10#issuecomment-5600257714). |
| Kyle Kingsbury: intent ordering | [Report](round-2/kingsbury/findings.md) | P2: older restoration strands newer Reveal. Fixed; 78 native and sanitizer checks pass. [PR comment](https://github.com/fastducduc/nv/pull/10#issuecomment-5600211154). |
| Contrarian: duplicate-row interactions | [Report](round-2/contrarian-ui/findings.md) | No new actionable finding; 71 native and sanitizer checks. [PR comment](https://github.com/fastducduc/nv/pull/10#issuecomment-5600211333). |

The other round-two reviews are in progress. Round 3 follows the second-round fixes.

## Validation limits

[Intel CI passed](https://github.com/fastducduc/nv/actions/runs/34335599567) at `e4d3ac4`, including native search suites, the app build, and archive checks.
Local builds use macOS 26.5.2 and Xcode 26.6; local native probes use arm64.
The copied Intel app cannot start on this host. Full desktop validation and a production UI screenshot remain unavailable.
Native or extracted-method fixtures do not establish full desktop behavior.

The 150 ms warm-search target remains unmet for the generated 10,000-note, 50 MiB corpus.
See [service measurements](../Measurements/README.md) and [native measurements](../Core/BENCHMARK.md).
