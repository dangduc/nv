# Round 3: space and token performance

This review uses a Dan Luu-inspired measurement perspective. It does not represent Dan Luu or his endorsement.

No new actionable findings. The corrected typesetter preserves native insertion points for long space runs and oversized tokens in these paired cases.
Repeated queries reuse completed layout without recreating paragraph measurements.
The resize measurements retain the added paragraph cost documented in round 1.

The reviewed production head is `63911bf2c66d438f178b43a8b9e996787e29acc9`.
The native control uses the pre-PR character-wrapping policy from `b6a5696`.
[The runner](run.py) links the frozen production typesetter and checks the common glyph delegate against both revisions.
The [README](README.md) describes reproduction and timing boundaries.

## New evidence

The fixtures contain 32,768 ordinary spaces or 32,768 `k` characters in a single token.
Both modes use native text views, Menlo 18, and the existing nonelastic-space glyph delegate.
The cases exercise eight width changes, 64 native end edits, and 256 repeated viewport and insertion-point queries.
Each width change requests layout through the caret at the source end. This includes the full note, not only its first viewport.

The [primary timing run](timing.json) used one warmup and six samples per mode, with alternating mode order.
The following values are median wall times for complete operation batches.

| Fixture | Operation batch | Native control ms | Candidate ms |
| --- | --- | ---: | ---: |
| spaces | resize | 39.989 | 48.545 |
| spaces | end-edits | 57.715 | 57.249 |
| spaces | cached-queries | 0.235 | 0.236 |
| long-token | resize | 40.705 | 51.368 |
| long-token | end-edits | 37.444 | 39.427 |
| long-token | cached-queries | 0.235 | 0.235 |

The resize difference is approximately 1.1–1.3 ms per width change in this fixture.
This confirms a residual cost, without the larger latency measured for longer prose paragraphs in round 1.
End editing remains less than 1 ms per operation on average in both modes.
These values do not define latency limits or predict complete nvALT frame times.

The [separate call-count run](counts.json) observed eight measurement snapshots covering 262,144 UTF-16 units during each resize batch.
Both resize fixtures made 7,048 cluster-break suggestions and created no CTLine objects through the custom implementation.
The spaces required no tokenizer advances. The unbroken token required 16 advances across eight resizes.

Each 64-edit batch created 64 measurements from native partial-layout ranges totaling only 4,700 UTF-16 units.
Those edits required 129 cluster-break suggestions and no custom CTLine creation in either fixture.
Repeated cached queries made zero measurement creations, cluster-break suggestions, tokenizer advances, or CTLine creations.
The absence of cache recreation supports the paragraph-cleanup result from round 2.

## Source and insertion-point invariants

Every paired case had identical native insertion-point histories, final insertion points, and visual line counts.
At the restored 544-point width, both fixtures occupied 669 lines in both modes.
Every insertion-point query asserted that the text view's logical selection remained at the source end.
Each completed case restored its exact original source and selection after all native edits.
These checks use Cocoa insertion-point geometry rather than an inferred character-width calculation.

The primary run passed 28,435 checks. The separate call-count run passed 4,063 checks, including evidence writes.
The runner also asserts the absence of custom measurement work during cached queries.

## Limits

The host used macOS 26.5.2 (25F84), x86_64 under Rosetta, with `-O1` and the macOS 10.13 deployment target.
The text views had no windows. Native editing selectors ran on the main thread, without the full nvALT event loop.
The source fixtures have no shaping complexity or mixed writing direction.
The evidence does not cover physical key input, caret painting, actual window resize events, display frames, or macOS 13.
Source setup was outside timing, while insertion-point queries and small history collections were inside timing in both modes.
Process CPU values include any internal AppKit worker work. They do not isolate main-thread CPU.
The root was running integration work, so small timing differences remain subject to host scheduling noise.
No production code or earlier review evidence changed.
