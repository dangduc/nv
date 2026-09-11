# Round 3: shaping across split attribute runs

Reviewed frozen correction `e022109eaf2bad6583512c2ed2b48561d9dae011` against `2ea92180939a3e51df8fe867ad548140ed455868`.
No actionable findings arose in these bounded cases.
Both arm64 and x86_64 passed 148 assertions and 12 exact layout comparisons.

The runner extracts both complete production callbacks through `git show` without changing their bodies.
Both layouts use the complete frozen `NVSourceTypesetter` implementation.
The candidate observer counts actual callback batches and forwards them to the unchanged callback.
It does not replace the classifier or implement a second property oracle.

## Native shaping evidence

Three short fixtures cover printable ASCII neighbors, non-ASCII neighbors, and composed or repeated spaces.
Unicode cases include accented Latin, CJK, a combining accent, an emoji sequence, and NBSP.
Ordinary spaces use font and attribute settings separate from adjacent word runs.
Adjacent word runs alternate Times New Roman and Helvetica, while spaces use Menlo.

Each fixture uses 86-point and 440-point containers.
The shaping variants change ligature settings, positive and negative kerning, and positive and negative baseline offsets.
Each source/width pair changes geometry or glyphs between shaping variants, for six positive controls per architecture.

All twelve candidate layouts match the pre-fix layouts exactly for:

- Glyph IDs, complete property buffers, UTF-16 mappings, and bidi levels.
- Line ranges, line rectangles, used rectangles, and glyph locations.
- Source code units and normalized attributed storage.

Each architecture records 56 actual one-glyph space callbacks across the split font runs.
Thus, the comparison covers separator batches whose neighboring source characters belong to other font runs.
The comparison also covers the composed-range fallback beside non-ASCII source characters.

## Deployment and limits

Both builds passed strict unguarded-availability checks.
The compiler flags include `-Werror=unguarded-availability` and `-Werror=unguarded-availability-new`.
`otool -l` reported macOS 10.13 for Intel and macOS 11.0 for arm64, matching the requested deployment targets.

Both executables ran on macOS 26.5.2 (25F84), with Xcode 26.6 (17F113).
Rosetta ran the Intel executable.
The results do not establish behavior on older macOS runtimes.

The probe uses native glyph generation and line layout without an application or GUI session.
Shaping attributes stress the AppKit boundary without a claim about the full editor's attribute-normalization policy.
It does not cover painted text, input methods, every font feature, or arbitrary Unicode context.
No production files, user notes, preferences, keychain items, commits, or PR comments changed.

## Reproduction

Run from the repository root:

```sh
python3 -B Tests/WrappedSeparatorReview/round3/platform/run.py
```

`results.json` contains source hashes, exact compiler commands, callback fonts, deployment metadata, and compact runtime observations.
Each process has a 45-second timeout.
The runner deletes its temporary source copies and executables after completion.
