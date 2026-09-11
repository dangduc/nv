# Round 2: performance and cache lifetime

This review uses a Dan Luu-inspired measurement perspective. It does not represent Dan Luu or his endorsement.

No new actionable findings. Earlier cache release reduced retained measurement state without adding measurement creation in the tested histories.
The existing long-paragraph cost remains documented in round 1. This review does not claim that cache cleanup removes that cost.

The reviewed correction is `4c8f6b449504a50caa460d78efebd42b94beaba6`.
The paired control is `4b049709b2cecc6eac80514586ccacc119d12802`.
[The correction clears analysis at paragraph completion](../../../../Sources/Editor/NVSourceTypesetter.m#L23).
The [runner](run.py) links both frozen production files, with a class-name substitution for the previous version.

## Hypothesis 1: early release adds measurement creation

The [instrumented histories](counts.json) created 76 measurement objects in each version, covering 370,633 UTF-16 units in total.
Creation counts and total measured text lengths matched at every recorded state.
Twenty repeated queries of already completed layout created no additional measurements.
Progressive viewport requests, source reattachment, and eight beginning edits also had matching creation counts.
Both versions released all 76 measurements after their text systems were destroyed.

These results reject added creation for the exercised histories.
They do not establish that every possible typesetter callback schedule has identical allocation behavior.

## Hypothesis 2: completed caches remain across empty storage or idle editors

The corrected version had no measurement object or line-break table at every recorded completed state.
The previous version retained the last paragraph's cache until later layout or destruction.

| State | Previous live snapshot units | Corrected live snapshot units |
| --- | ---: | ---: |
| Completed 16,000-character paragraph | 16,000 | 0 |
| Different empty storage attached | 16,000 | 0 |
| Eight beginning edits completed | 16,008 | 0 |
| Twelve idle text systems | 192,000 | 0 |

Each previous idle editor also retained a 25,600-byte line-break table in this fixture.
The corrected editor retained no completed line-break table.
Across the complete history, peak live snapshot length decreased from 192,000 to 16,008 UTF-16 units.
These lengths describe text associated with live measurement objects. They are not measurements of heap bytes or process memory.
The twelve text systems remained alive during the idle measurement, so destruction did not cause the reduction.

## Hypothesis 3: cache destruction adds short-edit latency

The [uninstrumented timing run](timing.json) used one warmup and seven trials per mode, with alternating order.
Each trial contained 192 text edits and native viewport layout calls on a short source fixture.

| Metric per 192 edits | Previous | Corrected |
| --- | ---: | ---: |
| Median wall time | 12.718 ms | 12.863 ms |
| Median process CPU time | 12.719 ms | 12.861 ms |
| Wall-time range | 12.083–12.926 ms | 12.754–13.248 ms |

The median difference was 0.145 ms across 192 edits, approximately 0.00076 ms per edit.
That difference does not support an actionable short-edit performance regression.
The separate creation-count run was excluded from these timings.

## Evidence limits

The native runs passed 47 checks, including evidence writes. The runner also asserts paired creation counts and completed-cache state.
The host used macOS 26.5.2 (25F84) and Intel binaries under Rosetta.
This is standalone main-thread text layout, without nvALT key-event dispatch, source analysis, autosave, drawing, or display-frame measurements.
The root was running build and integration work during this review. Small timing differences remain subject to host scheduling noise.
The fixture does not exercise physical input methods or macOS 13.
No production code or earlier review evidence changed.
