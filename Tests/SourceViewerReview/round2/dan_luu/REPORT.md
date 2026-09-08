# Round 2: Dan Luu-inspired measurement review

Baseline: PR #4, commit `f037c7b781fa2a3c58d7b00cb440ba3e7239b615`.
Date: September 8, 2026. This perspective emphasizes measurements and does not represent Dan Luu.

No actionable remaining defect was found in the display budget or tested transitions.
The independent probe confirms the Round 1 fix at its actual boundaries.

## Evidence

`boundary.m` compiles with the production highlighter and pinned Tree-sitter sources.
Each counting layout calls its real TextKit superclass and owns a text container.
The parser produces all HTML captures used in the display tests.
KVC installs those results to isolate synchronous application from parser time.
The source-edit test also exercises the real asynchronous worker and main-queue completion.

All 209 assertions passed in three separate processes.
The fixture counts calls to add and remove the private syntax attribute.
It also checks revision validity, unchanged stored attributes, and independent search backgrounds.

| Layouts | Accepted captures | Actual capture writes | First application, three runs | First rejected captures | Rejected writes |
| --- | ---: | ---: | --- | ---: | ---: |
| 1 | 4,096 | 4,096 | 2.795–3.061ms | 4,104 | 0 |
| 2 | 2,048 | 4,096 | 2.275–2.297ms | 2,056 | 0 |
| 3 | 1,360 | 4,080 | 2.076–2.109ms | 1,368 | 0 |
| 4 | 1,024 | 4,096 | 1.996–2.048ms | 1,032 | 0 |
| 20 | 200 | 4,000 | 1.696–1.733ms | 208 | 0 |

Real HTML emits eight captures per row, so the three- and twenty-layout cases bracket the limit at that granularity.
Reapplication stayed between 2.801ms and 3.011ms for accepted results.
Clearing accepted results took 1.094–1.224ms and issued one removal per highlighted layout.
Initially rejected results issued no additions or removals.

Adding a fifth layout to a 1,024-capture result cleared four prior layouts and performed zero capture writes.
Removing that layout restored all 4,096 writes from cached captures.
Detaching a highlighted layout invalidated its old revision.
Reattaching it removed the old attributes before installing the new revision.

A full-source shortening edit invalidated revisions immediately without changing temporary attributes during TextKit character processing.
The zero-delay cleanup removed four stale ranges before the 60ms analysis delay.
Changing to JSON then produced twelve writes across four layouts, with valid current revisions.

Worker checks passed for a cancelled generation, a 524,289-unit source, a 32,000-capture HTML fixture, and missing queries.
The expensive Markdown fixture returned fallback in 124.646–124.910ms.
A small JSON parse succeeded after the worker fallbacks.

## Negative control

The runner can compile a temporary copy with its display budget doubled to 8,192.
The fixture rejects that copy at the first 4,104-capture application with:

```text
FAIL: first application independently bounded
PASS: fixture rejects the doubled-budget mutant
```

The production file remains unchanged.

## Commands and outputs

Run from the repository root:

```sh
python3 Tests/SourceViewerReview/round2/dan_luu/run.py
python3 Tests/SourceViewerReview/round2/dan_luu/run.py --negative-control
```

The exact repeat command was:

```sh
python3 - <<'PY'
from pathlib import Path
import subprocess
root = Path.cwd()
for number in (2, 3):
    result = subprocess.run([str(root / 'build/source-viewer-review/round2-dan-luu/boundary'), str(root / 'Resources/Syntax')], text=True, capture_output=True, check=True)
    (root / f'Tests/SourceViewerReview/round2/dan_luu/output-repeat{number}.txt').write_text(result.stdout + result.stderr)
    print(f'Run {number}: {result.stdout.splitlines()[-1]}')
PY
```

Raw outputs: [first run](output.txt), [second run](output-repeat2.txt), [third run](output-repeat3.txt), and [negative control](negative-control.txt).

## Limits

The probe uses optimized x86_64 code under Rosetta on macOS 26.5.2 with Xcode 26.6.
It creates no window and accesses no user notes.
Timings cover synchronous parser or TextKit method calls, as identified above.
They exclude painting, glyph layout, and end-to-end typing latency.
The capture-write bound is a count per application, not a wall-clock guarantee or a cumulative lifetime limit.
Worker fallback timings include cleanup and can exceed the nominal 120ms cancellation deadline.
These results do not establish timing bounds on older hardware or macOS 10.13.
