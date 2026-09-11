# Round-one correction

The source paragraph style now uses `NSLineBreakByCharWrapping`.
The editor still clears `NSGlyphPropertyElastic` only for ordinary space glyphs.
Together, these settings let overflowing spaces move to the next visual line without moving an already-fitting word.
Words can split at the window edge. This is the chosen source-layout policy.

The common note-body attributes supply the paragraph style to new sessions, restored snapshots, font changes, and typing.
One immutable paragraph style is shared for the process lifetime.
This avoids allocating a new style for each note-body attribute request.
The change adds no key handling, caret drawing, source-character replacement, or custom typesetter.

## Findings

- P2: [The copied-app UX probe](ux/findings.md) checks the fitting-word reproducer and source editing after the correction.
- P3: [The copied-app performance probe](perf/findings.md) measures long-space reflow before and after the correction.

The original round-one reproducers and results remain unchanged.
They describe the initial glyph-only build, before the paragraph setting.

## Rejected approaches

A bounded investigation found no simple word-wrap configuration that also gave spaces the requested behavior.
The existing glyph adjustment produced fitting-word displacement with all six public legacy typesetter behaviors and four line-break strategies.
Keeping the first space elastic and treating spaces as whitespace control glyphs did not correct the displacement.

The public word-break veto only searched earlier boundaries in the measured cases.
It corrected `alpha beta` but moved more words in a longer prefix.
A prototype with Core Text width measurements required more line state and mishandled indents and tabs.
It also retained the expensive reflow for long runs of spaces.
These prototypes are not part of the application.

Native printing-character suffixes reproduced the same word displacement as the initial adjusted spaces.
This supports a native word-wrap policy interaction, rather than malformed glyphs or corrupted source.
Character wrapping selects a different native policy and avoids that interaction.
