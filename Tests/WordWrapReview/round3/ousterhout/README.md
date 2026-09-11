# Round 3: Ousterhout-inspired review

No actionable finding.
The production installation pattern retains each typesetter through its layout manager and releases it after replacement or owner teardown.
This review uses engineering priorities inspired by John Ousterhout. It does not represent his authorship or endorsement.

Reviewed revision: `63911bf2c66d438f178b43a8b9e996787e29acc9`.
The production typesetter hash remains `c8045359e5d821a3c8ae55abb454de4a979cfa15273b25380152847bfe7b71f9`.
The primary integration boundary is `LinkingEditor.m:64`, which assigns an autoreleased typesetter to the layout manager.

## Executed evidence

The compact headless probe passes 27 checks on arm64 and x86_64.
It links the current production implementation and imports the previous observer and attribute helpers.
The previous test entry point is renamed and never called.
The actual editor glyph callback is extracted by the established harness helper.

Two new boundaries were tested:

- Native layout must retain the autoreleased production instance after its installation pool drains.
- Replacement and teardown must preserve deferred geometry and the surviving peer's shared source.

Two layout managers share one source and use different widths.
Each typesetter has no extra owning test reference after installation.
Both instances remain alive after the installation pools drain.
The source contains three paragraphs with distinct font and alignment attributes.
Layout queries occur only after the source-attribute creation pool also drains.
The resulting source attributes remain unchanged.

One manager receives four replacement typesetters through the same autorelease pattern.
Each replacement destroys its predecessor and retains its successor.
Line ranges, rectangles, used rectangles, and first-glyph positions remain identical before and after replacement.
Complete glyph regeneration produces the same geometry.
The peer layout and shared source attributes remain unchanged throughout.

After the first manager is detached and released, its native temporary objects are drained.
Its typesetter is then destroyed, while the peer still supplies the expected geometry.
The final teardown destroys all six observed typesetter instances.
The production word-boundary path narrows 27 line fragments during each run.

## Reproduce

```sh
python3 Tests/WordWrapReview/round3/ousterhout/run.py
```

Host: macOS 26.5.2 (25F84).
The runner targets macOS 11 for arm64 and 10.13 for x86_64. The Intel process runs through Rosetta.
`results.json` records the revision, source hash, checks, and instance counts.
Generated binaries and logs are under `build/WordWrapReview/round3/ousterhout/`.
No windows, preferences, or personal notes are accessed.

## Limits

This review does not cover app window restoration, painted frames, or physical input.
Typesetter replacement exercises the native ownership boundary. The current app installs a typesetter once during editor setup.
The probe compares line geometry and first-glyph positions, not every glyph.
It does not measure heap memory or establish behavior on macOS 13.
The initial teardown assertion ran before native temporary objects left the autorelease pool.
The final assertion drains that pool first and observes complete destruction without a remaining owner cycle.
The previous round already includes a negative control for omitted paragraph cleanup. This round adds direct instance-lifetime observations.
