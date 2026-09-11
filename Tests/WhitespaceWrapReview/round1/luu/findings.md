# Round 1: measured performance

This review uses a perspective inspired by Dan Luu. It does not represent his review or endorsement.

Reviewed commit: `83a7307`, against base `f772c4b`.
Environment: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), Intel code under Rosetta.

## P3: very long space paragraphs make native word wrapping expensive

The adjustment exposes a slow native layout path for long paragraphs that contain only ordinary spaces.
The measured trigger is a viewport layout request after the container width changes from 480 to 160 points.
The request uses `ensureLayoutForBoundingRect:inTextContainer:` with a 400-point viewport height.
AppKit still lays out the whole paragraph in these cases.

| Contiguous spaces | Default native layout | Adjusted word wrapping | Adjusted character-wrapping control |
| --- | ---: | ---: | ---: |
| 4,096 | 0.92 ms | 3.89 ms | 0.95 ms |
| 8,192 | 1.89 ms | 12.69 ms | 1.91 ms |
| 16,384 | 3.21 ms | 45.28 ms | 3.84 ms |
| 32,768 | 5.63 ms | 168.14 ms | 7.53 ms |

Each value is the median of three trials. Mode order rotates between trials.
The adjusted cost grows much faster than the source length.
This reflow performs zero glyph-generation callbacks, so allocation changes in the new delegate cannot remove this cost.

The initial full-layout control gives the same distinction.
At 160 points, 32,768 adjusted spaces occupy 1,639 lines and take 170.52 ms.
The delegate itself takes 0.52 ms across all 32 callbacks.
The same number of native Menlo `x` characters occupies the same number of lines in approximately 13 ms.
Thus, extra line count alone does not explain the cost.
The character-wrapping control supports a native word-break interaction as the explanation.
This evidence does not identify a specific internal AppKit algorithm.

This is a low-priority edge limit because the slow cases contain thousands of contiguous spaces.
The short-note and prose cases show no comparable regression.
Thirty incremental appends to the 32,768-space case improve from 217.30 ms to 11.10 ms at 160 points.

Document this limit and retain the probe for later layout work.
Global character wrapping is not an acceptable correction because it changes normal prose wrapping.
A future correction needs an ordinary-prose control and a reason to justify added paragraph policy.
No actual nvALT live-resize frames were measured in this review.

## Ordinary-case results

The script extracts the production delegate method verbatim from `LinkingEditor.m`.
A macro counts only its `malloc` calls. A subclass times calls to the extracted method.
Native and no-op delegate controls expose the measurement overhead.
No fabricated glyph batches enter the delegate.

- Native batches contain at most 1,024 glyphs in these fixtures.
- The maximum temporary allocation is 8,192 bytes. Every changed batch has exactly one allocation.
- The 100,000-character prose fixture uses 98 batches and 800,000 total allocation bytes, released one batch at a time.
- At 480 points, that fixture takes 33.93 ms with native layout and 34.49 ms with the adjustment.
- Its measured delegate time is 0.70 ms. Both layouts contain 3,125 lines.
- The 1,024-character prose fixture takes 0.388 ms native and 0.394 ms adjusted at 480 points.
- Initial tab-only and space-free fixtures perform no delegate allocations. Their line counts remain unchanged.
- Thirty appended spaces regenerate 465 glyphs in the prose fixtures, rather than their complete source.
- Width-only reflow performs no glyph generation in all measured full-layout fixtures.
- At 160 points, thirty appends to 32,768 spaces regenerate 965 glyphs after the adjustment.
- The no-op control regenerates 983,505 glyphs for that same sequence.

## Reproduction and limits

Run `python3 Tests/WhitespaceWrapReview/round1/luu/run.py` from the worktree.

The probe passed 540 full-layout stages and 270 viewport-layout stages.
Every stage checks source preservation. Wrapping controls check equal line counts for spaces and native monospace letters.
The script also checks allocation counts and the absence of glyph generation during width-only reflow.
It uses fresh native `NSTextView` instances, in-memory source, and the shared GUI lock.
It opens no nvALT app, preferences, or note library.

`results.json` and `visible-results.json` contain median measurements.
Full trials and the generated source remain under ignored `build/WhitespaceWrapReview/round1/luu`.
These measurements cover Menlo 12 at 160 and 480 points on this host.
They do not establish macOS 13 performance, visible frame timing, every font, or every source format.
The callback timer includes instrumentation overhead; its values are an upper estimate of the delegate cost.
