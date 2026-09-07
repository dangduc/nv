# Round 1: empirical performance review

AI review perspective inspired by Dan Luu. Reviewed commit `30791c5` against `4c6cf45` for PR #1. These are independent measurements, not statements by Dan Luu.

## Finding LUU-R1-1 — P2: Preserve incremental search within each browser

**Location:** `NVBrowserSession.m:119-126`, reached synchronously from `AppController.m:1369` on search-field edits.

Each query change discards the browser's filtered candidates and scans the full library. Extending an already empty query therefore reads every note again. The base implementation in `NotationController.m` keeps the existing candidates when the new query extends the old prefix. Moving the candidate state into a browser should preserve that behavior without reusing per-note match cursors.

Run:

```sh
python3 Tests/ReviewEvidence/round1/luu/run-search-scaling.py
```

The probe compiles the production `NVBrowserSession.m` with in-memory model doubles. It also extracts and executes the base commit's actual filter method and note predicate. Autocomplete is disabled in both paths. The fixture contains ASCII notes with 2,048-character bodies.

| Notes | New note-content reads when extending `absent` to `absentx` | New latency | Base latency |
| ---: | ---: | ---: | ---: |
| 1,000 | 1,000 | 12.107 ms | Below timer resolution |
| 10,000 | 10,000 | 122.869 ms | 0.001907 ms |
| 25,000 | 25,000 | 299.210 ms | 0.001073 ms |

**Expected:** A compatible query extension filters the browser's existing candidate set; extending zero results examines zero notes until the library changes.

**Observed:** The new session performs one content read per library note. At 10,000 notes, this adds about 123 ms of synchronous search work per character in this fixture. Timings are machine-specific; the read count is deterministic.

**Requested change:** Keep the candidate set and query-refinement state in `NVBrowserSession`, invalidate them on relevant library changes, and avoid sorting an unchanged result set. Add an access-count regression for zero-result refinement and retain interleaved-window coverage. `NVApplicationController.m:199-220` also schedules this full refresh in each browser after edits; edit-to-display latency was not measured here.

## Checks without findings

- Interleaved searches in two production sessions retained independent result counts at all three fixture sizes.
- `run-undo-memory.py` compiles the production editing session with an in-memory note double. Two hundred one-character edits to a 1 MiB note grew measured physical footprint by 2.703 MiB; 200 undos restored the original content. This does **not** support the initial hypothesis that snapshots necessarily retain 200 full note buffers.
- Four hundred edits left 200 undo actions, matching the explicit history limit. Returning only to the state 200 edits earlier is expected under that limit.

## Scope and reproduction

Measured on macOS 13.7.8, arm64, Apple clang 15.0.0, with `-O2`. These probes create no app windows or files in a notes library. They do not build or modify the shared app. The search fixture uses model doubles and no table rendering; production Intel/Rosetta UI latency may differ. Sorting-only figures printed by the probe use the session's fallback title comparator and are not used to establish the finding.

Raw output is in ignored `build/pr-review/round1-luu/`. Executables use temporary directories and are removed after execution. Deleted-note retention is assigned to another reviewer; this review makes no finding about it.
