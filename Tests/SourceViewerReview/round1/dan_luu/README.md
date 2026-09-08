# Round 1: Dan Luu-inspired performance review

Baseline: PR #4, commit `5e44a909bd6b7b2ad1957c475f94594e0bffd461`.
This review uses measurement and workload boundaries. It does not represent Dan Luu.

Run from the repository root:

```sh
python3 Tests/SourceViewerReview/round1/dan_luu/run.py
```

The probe compiles the production parser and highlighter for x86_64 with `-O2`.
It runs Foundation and TextKit under Rosetta without a window or access to user notes.
It measures parser work separately from calls to the production `applyCaptures` method on the main thread.
The result comes directly from the production parser. The probe uses KVC to install that result in the production highlighter.
Each layout has its own text container. The fixture uses one, two, four, and twenty layouts on shared storage.
`measurements.csv` records a fresh empty-capture control, first application, three-call median, and removal cost.
The median includes the first application. It is not an end-to-end typing measurement.

## Confirmed finding

**P2: Bound syntax attribute work on the main thread.**

Location: `Sources/Editor/NVSourceHighlighter.m:274–280`, especially line 278.
The `analyze` completion invokes this loop on the main thread at lines 297–300.

A valid 90,780-unit HTML note with 3,000 short paragraphs produces 24,000 captures.
It stays below the 524,288-unit size limit, 30,000-capture limit, and 120ms parser budget.
Three independent runs measured first display application at about 62–66ms for one layout,
124–129ms for two layouts, and 246–254ms for four layouts. Twenty layouts took 1.2–1.35 seconds.
These numbers exclude parsing, painting, glyph layout, and window management.
They therefore establish a main-thread stall from syntax attribute application alone.
For four layouts, subsequent application measured roughly 71–88ms.

The loop updates every capture in every attached layout within one main-queue block.
The worker budget cannot interrupt this work. Restoring several windows on the same source,
or attaching another source editor, can stall input while applying an accepted result.
The shared storage retains hidden source layouts while a window displays Preview, so those layouts also receive this work.

Give display application its own bounded workload. Possible fixes include resolving overlapping captures into ordered runs
before display and using a layout-count-aware fallback, or applying bounded chunks with revision checks.
Preserve the existing rule that temporary attributes must not change during TextKit character processing.
A regression should measure first application as well as parser time, and include at least four attached layouts.

## Negative results and limits

- Small JSON, HTML, and Markdown notes stay inexpensive in the fixture.
- The larger HTML fixture returns plain fallback after exceeding the capture count.
- Large Markdown fixtures return fallback in approximately 123–125ms. The worker time bound works for these inputs.
- The capture limits bound total memory, but do not provide a display latency bound.
- No GUI, painting, or end-to-end keystroke timings were measured. No claim depends on those measurements.
- No production files were changed for this review.
