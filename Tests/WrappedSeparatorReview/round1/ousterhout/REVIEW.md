# Round 1: locality and shared-layout ownership

This Ousterhout-inspired review covers PR 30 at frozen commit `9e6c8dd6adc058e7044f2c562532af97dd4e63d4`, against `75d6f42`.
It is an engineering perspective, not a review by John Ousterhout.

No actionable findings.

The change keeps separator classification inside the existing glyph delegate.
It adds no editor override, notification observer, shared cache, or controller owner.
The guard runs before the existing property-buffer allocation and preserves the native result for an eligible separator.
The composed-character check keeps spaces with attached marks literal.
The inspected diff leaves the shared storage and per-layout typesetter contracts intact.

## New executable evidence

Command:

```sh
python3 -B Tests/WrappedSeparatorReview/round1/ousterhout/run.py
```

Both architectures passed: arm64 and x86_64 under Rosetta.
Each process completed 36 production-layout comparisons and reported 296 checks, including its final result write.
The runner extracts the actual glyph hook, typesetter implementation, and typesetter header through `git show` at the frozen commit.
The JSON records their hashes and the environment.
The earlier invalidation research does not count as this round's evidence.

The new probe compares cached glyph IDs, properties, positions, and line geometry with a fresh production layout after each operation.
Two layouts share one text storage, use different widths, and own separate production typesetters.
The second layout permits noncontiguous layout.
Spaces use separate font and color runs.

Cases cover combining marks, variation selectors, joiners, nonbreaking neighbors, mixed text and attribute batches, and attribute-only changes.
Additional cases move one layout to another note, edit each note independently, reattach the layout, and reuse both layouts through an empty note.
Editing one note generated no glyphs in the layout attached to the other note.
Every observed space property matched the requested policy, and every cached layout matched its fresh reference.
Layout left source characters and attributes unchanged.

## Limits

The probe uses the complete native text-storage and layout objects with the actual production hook and typesetter.
It does not launch the full application, create windows, or exercise input-method composition through a text view.
It simulates character and attribute mutations directly through native text storage.
The results apply to macOS 26.5.2 with Xcode 26.6, not all supported macOS versions.
The probe reads no personal notes, application preferences, or keychain items.
No GUI lock was necessary because it creates no GUI session.
No production files, commits, or PR comments changed during this review.
