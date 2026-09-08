# Round 3: Dan Luu-inspired viewport measurement review

Baseline: PR #4, commit `9720676ccd0e619dba99f6a47d257216c1e383eb`.
Date: September 8, 2026. This perspective emphasizes measurements and does not represent Dan Luu.

No actionable regression was found in the Source restoration layout request.
The measured work depends on the saved viewport depth, rather than the complete source length, for these fixtures.
This review adds a separate measurement from the prior highlighting-budget probes.

## Method

`run.py` extracts the current production `restoreSourceScroll` method without changing it.
`viewport.m` compiles that method into a host with fixed geometry and recorded scroll messages.
Real `NSTextStorage`, `NSLayoutManager`, and `NSTextContainer` objects perform all layout.
A layout-manager subclass counts line-fragment writes; its delegate counts generated glyphs without changing them.
`firstUnlaidCharacterIndex` measures layout progress without requesting further layout.

The fixture contains numbered 44-character lines in a fixed-pitch 12-point font.
The two source lengths are 88,000 and 528,000 characters, with 2,000 and 12,000 lines.
These synthetic sources isolate scaling. They do not represent measured user note sizes or typical editing activity.
The geometry is 780 by 480 points. Saved vertical offsets are 0, 700, and 6,000 points.

All 41 assertions passed in three separate processes.

| Saved offset | Source lines | Characters laid out | Line fragments | Glyphs generated | Elapsed time, three runs |
| --- | ---: | ---: | ---: | ---: | --- |
| 700 | 2,000 | 3,784 | 86 | 8,192 | 11.281–11.854 ms |
| 700 | 12,000 | 3,784 | 86 | 8,192 | 2.389–2.852 ms |
| 6,000 | 2,000 | 20,416 | 464 | 24,576 | 7.875–8.489 ms |
| 6,000 | 12,000 | 20,416 | 464 | 24,576 | 7.737–8.263 ms |
| Full-document control | 2,000 | 88,000 | 2,000 | 88,000 | 23.276–24.306 ms |
| Full-document control | 12,000 | 528,000 | 12,000 | 528,000 | 145.548–148.079 ms |

The first nonzero restoration runs before font/layout initialization is warm in each process.
Its higher elapsed time does not imply that the shorter source requires more work.
The operation counts provide the scaling evidence.
AppKit generates glyphs ahead of the laid-out range; those counts also stayed equal across source lengths.

A zero Source offset requests no layout or glyph generation.
Restoring while Source is hidden also requests no layout or glyph generation.
Every production case sends the saved point to the scroll target.
The requested rectangle ends at the saved offset plus viewport height.

## Negative control

The runner can replace the bounding-rectangle call in its temporary extracted method with `ensureLayoutForTextContainer:`.
Production files remain unchanged.
At offset 700, the mutant lays out all 88,000 characters and generates all 88,000 glyphs.
The fixture fails its actual-work assertion before checking the requested rectangle:

```text
FAIL: near-top restoration avoids most document layout
PASS: probe rejects full-document-layout mutant
```

## Commands and outputs

Run from the repository root:

```sh
python3 Tests/SourceViewerReview/round3/dan_luu/run.py
python3 Tests/SourceViewerReview/round3/dan_luu/run.py --negative-control
```

The repeat command was:

```sh
python3 - <<'PY'
from pathlib import Path
import subprocess
root = Path.cwd()
for number in (2, 3):
    result = subprocess.run([str(root / 'build/source-viewer-review/round3-dan-luu/viewport')], text=True, capture_output=True, check=True)
    (root / f'Tests/SourceViewerReview/round3/dan_luu/output-repeat{number}.txt').write_text(result.stdout + result.stderr)
    print(result.stdout)
PY
```

Raw outputs: [first run](output.txt), [second run](output-repeat2.txt), [third run](output-repeat3.txt), and [negative control](negative-control.txt).

## Limits

The probe compiles optimized x86_64 code under Rosetta on macOS 26.5.2 with Xcode 26.6.
It creates no window and accesses no user notes.
It measures synchronous restoration layout, including glyph generation; it excludes painting and end-to-end mode-switch latency.
The geometry host records `scrollPoint:` without exercising a real clip view's clamping behavior.
The repository's desktop workflow tests cover that separate behavior.

The method lays out from the source start through the saved viewport, so deeper restoration requires more work.
These results do not promise constant-time restoration for arbitrary offsets or bound a full-document restoration near the end.
They do not cover different fonts, long unbroken paragraphs, bidirectional text, older hardware, or macOS 10.13.
