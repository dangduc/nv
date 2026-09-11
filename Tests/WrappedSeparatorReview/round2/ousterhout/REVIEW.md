# Round 2: request order and layout-local state

This Ousterhout-inspired review covers frozen commit `2ea92180939a3e51df8fe867ad548140ed455868` in PR 30, against `75d6f42`.
It is an engineering perspective, not a review by John Ousterhout.

No actionable findings.
The production change remains unchanged from round one.
The new evidence supports the current ownership boundary: shared storage owns the text, while each layout owns its typesetter and glyph cache.
The separator rule needs no additional protocol between layouts.

## New executable evidence

Command:

```sh
python3 -B Tests/WrappedSeparatorReview/round2/ousterhout/run.py
```

The runner extracts the actual production hook and typesetter from the frozen commit.
Both arm64 and x86_64 passed 2,670 checks and 162 layout comparisons each.
The JSON records the source hashes, environment, and compact results.

Three native layouts share storage, use distinct widths, and own separate production typesetters.
The probe runs nine new states through all six request orders.
Each result matches fresh production glyphs, properties, positions, and line geometry.
Each result also matches the corresponding state from the first request order.

New histories include these operations:

- Targeted glyph invalidation within split font runs, an attached mark, and a paragraph boundary.
- Font changes, paragraph joins, and disjoint composed-character edits within a batch.
- Temporary movement of the middle layout to another note, independent edits, and reattachment.
- Separate width changes after all three layouts share the note again.

Layout leaves source characters and attributes unchanged.
All 324 completed-layout inspections found no retained paragraph measurement or line-break table in the production typesetter.
The fixture removes every layout attachment before each history ends.

## Limits

The probe reuses round-one helper code but runs new histories with three layouts and explicit request-order comparisons.
It uses native AppKit objects and the frozen production code on macOS 26.5.2 with Xcode 26.6.
It does not launch the application, create windows, or cover earlier macOS versions.
The typesetter-state inspection is specific to the paragraph caches and is not a general memory-leak audit.
No personal notes, preferences, or keychain items are accessed.
No GUI lock was necessary because the probe creates no GUI session.
No production files, commits, or PR comments changed during this review.
