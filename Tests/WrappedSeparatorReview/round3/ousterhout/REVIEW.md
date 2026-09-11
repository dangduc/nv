# Round 3: callback locality and query budget

This Ousterhout-inspired review covers frozen commit `e022109eaf2bad6583512c2ed2b48561d9dae011` in PR 30.
It compares the shortcut with `2ea9218` and retains the original `75d6f42` scope.
It is an engineering perspective, not a review by John Ousterhout.
This reviewer implemented the round-two correction, so this record is a targeted self-review.

No actionable findings.
The shortcut stays inside the existing bounded-neighbor guard.
The callback reads each neighbor once and retains the composed-range fallback for other eligible contexts.
It introduces no invalidation hook, shared owner protocol, or stored classification state.

## New executable evidence

Command:

```sh
python3 -B Tests/WrappedSeparatorReview/round3/ousterhout/run.py
```

Both arm64 and x86_64 passed 2,104 checks, 28 shared-layout comparisons, and 376 callback-budget checks each.
The callback-budget count includes fresh reference layouts.
The runner extracts the actual production hook and typesetter through `git show` at the frozen commit.
The JSON records their hashes, environment, and compact measurements.

Two layouts share native text storage and use separate production typesetters.
New attributed-edit histories change ASCII neighbors to Latin, CJK, combining-mark, and whitespace contexts, then restore ASCII.
Another history combines disjoint Unicode replacements with an attribute change.
Boundary cases cover printable ASCII endpoints and the adjacent DEL code point.

Representative measurements from each architecture:

| Context | Direct character reads | Composed-range queries |
| --- | ---: | ---: |
| Three ASCII separators | 9 | 0 |
| One Latin, CJK, or attached-mark transition | 9 | 1 |
| Two Unicode contexts in one batch | 9 | 2 |
| ASCII restored after those edits | 9 | 0 |
| Printable endpoints `! ~` | 3 | 0 |
| DEL neighbor outside the printable range | 3 | 1 |

Every measured callback met its budget from the native input glyph candidates.
Each bounded space required two neighbor reads after its candidate read.
ASCII restoration removed the fallback query immediately, with no stale context from another edit or layout.
Cached glyphs and geometry always matched fresh production layout.
Layout preserved source characters, attributes, and shared-storage ownership.

## Limits

Instrumentation wraps the concrete storage-string methods only in this disposable process and forwards their original implementations.
Counters are active only during the unchanged production callback.
Direct character-read counts exclude Foundation's internal work inside a composed-range query.
These are operation counts, not timing measurements or guarantees about Unicode fallback complexity.

The probe uses macOS 26.5.2 and Xcode 26.6 without a complete application or text-view input session.
It creates no GUI session and accesses no personal notes, preferences, or keychain items.
No production files, commits, or PR comments changed during this round.
