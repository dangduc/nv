# Round-two correction

The P3 performance finding is addressed in `e022109eaf2bad6583512c2ed2b48561d9dae011`.
The Ousterhout reviewer implemented the correction; the primary agent inspected the diff and rebuilt the app.
Round three independently reviews the corrected production code.

The callback reads each neighbor once after checking the source bounds.
When both neighbors are U+0021 through U+007E, the space is a separate composed character.
That case skips the Foundation composed-range query.
All other eligible separators retain the full composed-character guard.
The glyph buffer, source data, editing behavior, and layout ownership remain unchanged.

The maintained negative control now asserts that it found the separator guard before disabling it.
Both architecture controls rejected the former wrap behavior at the expected assertion.
The positive suites passed 10,316 assertions per architecture.

The corrected Intel Development build passed on macOS 26.5.2 with Xcode 26.6.
Its copied-app separator suite passed 32 assertions.
The existing wrapping suite passed 74,736 assertions per architecture and 1,305 copied-app assertions.
The corrected app SHA-256 is `b28da33e5f645a589f4802d778225693f7e0764abf6a48a21690d154421ad40c`.

Both required desktop suites ran again.
The multiwindow suite reproduced its documented library-replacement failure, with exit 245.
The aggregate suite stopped at the recorded Fuzzy UI activation failure; later entries did not run.
See [validation](../../WrappedSeparators/VALIDATION.md) for details and limits.

[Published correction comment](https://github.com/dangduc/nv/pull/30#issuecomment-5640178119).
