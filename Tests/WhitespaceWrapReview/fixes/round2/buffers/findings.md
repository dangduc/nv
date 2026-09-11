# Round 2: glyph-buffer optimization

The glyph delegate now avoids heap allocation for batches of at most 64 properties.
It also returns before reading text storage when no glyph has an eligible elastic property.
Larger changed batches retain the checked heap fallback.

Only `Sources/Editor/LinkingEditor.m` changes production behavior in this patch.
The source checks, glyph IDs, source indexes, font, ranges, other properties, and native fallback remain unchanged.
The delegate performs no layout query and changes no source, key, caret, or selection behavior.

## Evidence

The runner extracts the old production method from `072a6bc0f54a52603f8cedfbcacc17d0ab836a36` and the new method from the working tree.
It inserts both methods verbatim into separate delegates.
Macros count their explicit `malloc` and `free` calls and can simulate allocation failure.
The executable uses AddressSanitizer and UndefinedBehaviorSanitizer on Intel under Rosetta.

The guarded-input suite passes 465 checks, including the final evidence-write check.
Its 54 comparisons cover batch lengths 0, 1, 2, 63, 64, 65, 127, 268, and 1,024.
The buffers end at inaccessible guard pages.
Fixtures cover ordinary spaces, non-space elastic characters, control glyphs, other property flags, and out-of-range source indexes.
One pattern places the only eligible glyph at the final input position.

- All old and new return values and published arrays match under normal allocation.
- All glyph, property, and source-index inputs remain unchanged.
- The 22 empty or ineligible-property cases perform no storage or string reads in the new method.
- Only changed batches larger than 64 allocate, and each allocation has one matching release.
- Simulated heap failure in larger batches returns zero without publication or an invalid release.
- Small batches still work when the allocator rejects all heap requests.
- Empty and overflowing length guards return before any array or source access, including with null input arrays.

The native TextKit suite passes 271 checks, including its evidence-write check.
Its 54 cases cover Menlo, Helvetica, Times, three widths, spaces, tabs, Vietnamese text, combining text, emoji, Chinese text, and bidirectional text.
The source uses the current character-wrapping paragraph policy.
Every glyph ID, property, source mapping, position, line range, and line rectangle matches the old production method.
Source characters remain unchanged.

The native matrix performs 81 heap allocations with the old method and 27 with the new method.
Its largest heap allocation is 8,192 bytes.
The new local buffer occupies 512 bytes on this tested architecture and never grows with the batch length.

## Reproduction and limits

Run `python3 Tests/WhitespaceWrapReview/fixes/round2/buffers/run.py` from the worktree.

`results.json` contains the compact counts.
Generated source, binaries, and logs remain under ignored `build/WhitespaceWrapReview/fixes/round2/buffers`.
The native phase uses the shared GUI lock and in-memory text; it opens no nvALT note library.

The allocation counts describe these specific fixtures, rather than app-wide allocator traffic.
The unit publication capture copies arrays synchronously, and the separate native comparison checks their subsequent TextKit results.
This suite establishes semantic equivalence and bounded buffer behavior; the copied-app performance experiment measures the actual resize improvement separately.
It does not establish every font, every callback shape, or macOS 13 behavior.
