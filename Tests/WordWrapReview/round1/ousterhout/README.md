# Round 1: Ousterhout-inspired review

One P3 finding: completed paragraph caches outlive the paragraph and remain attached after switching to an empty note.
This review uses engineering priorities inspired by John Ousterhout. It does not represent his authorship or endorsement.

Reviewed revision: `4b049709b2cecc6eac80514586ccacc119d12802`, against `b6a5696`.
The scope is the typesetter abstraction, per-layout ownership, and cache lifecycle.

## P3: Release completed paragraph caches at paragraph completion

Location: `Sources/Editor/NVSourceTypesetter.m:7–15`, with release also present at `123–126`.
The implementation releases the previous measurement and break table only when another paragraph begins or the typesetter is destroyed.
An empty note does not begin another paragraph.
The last completed paragraph therefore remains cached after its layout manager moves to an empty note.
There is no size limit on that cached paragraph below the existing integer-range guard.

The executable reproducer creates a 65,536-character paragraph from repeated `alpha beta gamma delta epsilon ` text.
It lays out the paragraph at 544 points with Menlo 18.
It then detaches the layout manager, attaches empty storage, clears the original source, and drains the temporary autorelease pool.
The production instance still holds an 84,568-byte break table.
Its cached Core Text typesetter can still construct the complete 65,536-glyph line from the previous paragraph.
Both arm64 and x86_64 reproduce this result.

This retains avoidable paragraph analysis data until a future nonempty layout or editor destruction.
Each editor owns an independent cache, so this storage is additional to the shared note source.
This is retention beyond the useful lifetime, not an object leak that survives typesetter destruction.

Recommendation: release the measurement and break table from `endParagraph`, after the native implementation finishes that paragraph.
A small private cleanup method can centralize the existing release/reset sequence.
Keep defensive cleanup in `beginParagraph` and `dealloc`.

The test-only subclass implements that exact cleanup after forwarding `endParagraph` to production.
All lifecycle and fresh-layout assertions still pass on both architectures.
The old paragraph then contributes zero cached glyphs and zero break-table bytes after the empty switch.
This is a focused correction experiment; the production file remains unchanged.

## Other executed evidence

The runner links the actual `NVSourceTypesetter.m`.
It extracts the actual editor glyph callback with the existing harness's brace scanner.
It does not duplicate the line-break algorithm.
The observer subclass forwards native lifecycle methods and counts the production narrowing path.
No windows, personal notes, or preferences are accessed.

Each of four runs passes 148 checks: production and the cleanup experiment on arm64 and x86_64.
Each run exercises 4,497 narrowed line fragments, 481 paragraph begin/end pairs, and 109 typesetter creations and destructions.

Twelve independent lifecycle cases cover these operations:

- Two layout managers share one source while owning separate production typesetters.
- Partial layout is followed by a same-length source edit and paragraph font/alignment changes.
- Incremental line boundaries, rectangles, and first-glyph positions match fresh production layouts.
- Width and padding changes produce the same results as fresh layouts.
- Detaching one manager preserves its peer's source and line geometry.
- Empty-note reuse and original-note reattachment reset measurement state correctly.
- Color changes leave incremental geometry consistent with fresh layouts.
- All 109 observed typesetter instances are destroyed after their owning systems leave scope.

No source mutation, cache contamination, or stale-layout result was observed in these cases.
The source attributes remain unchanged during partial layout.
Only the explicit five-character replacement changes source characters.

## Reproduce

```sh
python3 Tests/WordWrapReview/round1/ousterhout/run.py
```

Host: macOS 26.5.2 (25F84).
The runner compiles arm64 with deployment target 11 and x86_64 with deployment target 10.13.
The Intel probe runs through Rosetta.
`results.json` records the revision, production-file hash, counters, and cache observations.
Generated executables and logs are under `build/WordWrapReview/round1/ousterhout/`.

## Limits

This headless review does not cover painted frames, mouse or keyboard events, input-method composition, or macOS 13 behavior.
The geometry comparison records each line and its first glyph; it does not compare every glyph position.
The cleanup experiment supplies bounded evidence for lifecycle correctness, not a complete validation of all native callback orders.
The retained break-table size is measured directly.
The Core Text result proves retained paragraph data, but the probe does not measure its physical memory footprint.
An exploratory custom-attribute ownership marker also remained in framework caches after typesetter destruction, so it was unsuitable for isolating this cache.
The final reproducer instead reads the actual retained Core Text measurement and production break table.
