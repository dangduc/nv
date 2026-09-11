# Round 3: selection and word navigation

No new defect was found in these focused editing checks.
The reviewed revision is `63911bf2c66d438f178b43a8b9e996787e29acc9`.
Its production typesetter is unchanged from round two.

Each architecture passed 1,694 assertions across four cases.
The fonts were Menlo and Helvetica at 18 points.
The container widths were 160.1 and 239.9 points.
The source included ordinary words, a long identifier, 36 consecutive spaces, blank paragraphs, CRLF, accented text, and a composed emoji.

The native reference uses the same source, attributes, and production space callback.
It omits only the custom typesetter.
The layouts placed 231 source characters on different visual rows.
The production layouts also contained six complete rows of ordinary spaces.
These differences establish that the comparison exercises wrapped text and overflowing spaces.

The first check compares word and paragraph selection at thirteen source positions and one extended source range.
All 112 proposed selections returned the same source ranges as native `NSTextView`.
The positions include spaces, paragraph separators, an identifier interior, accented text, and an emoji.

The second check compares word navigation and selection extension.
Four commands run three times from each of four source positions.
All 192 commands returned the same source indexes as native `NSTextView`.
The commands are Word Right, Word Left, and their selection-extension forms.

Two additional selected ranges cross visual wraps, overflowing spaces, and paragraph breaks.
All 1,272 sampled insertion intervals had the expected selection coverage.
The selection rectangles covered selected intervals and excluded unselected intervals.
Both text views retained the exact source after all commands.

The probe includes the [round-one Cocoa helpers](../../round1/contrarian_ux/probe.m), but it does not run their matrix.
It links the actual production typesetter and reuses the production callback scanner from `Tests/WordWrapping/run.py`.
The comparison does not reproduce the boundary algorithm.

Run from the frozen worktree:

```sh
python3 Tests/WordWrapReview/round3/contrarian_ux/run.py
```

The runner records source identity, counts, and observation hashes in `results.json`.
The arm64 and x86_64 observation hashes match.
The host was macOS 26.5.2, with Intel execution through Rosetta.
The compiler targets were macOS 11 for arm64 and macOS 10.13 for x86_64.
The runner deletes temporary binaries after the run.

These headless native API checks do not cover physical double-clicks, mouse dragging, event dispatch, painted selection pixels, or older macOS releases.
The probe created no windows and changed no personal notes, preferences, or production files.
