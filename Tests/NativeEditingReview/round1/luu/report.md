# Round 1 — Dan Luu review

## Medium — Manual completion still substitutes nv note titles

The simplification removes `LinkingEditor`'s automatic note-link completion,
but `AppController` remains the source editor's delegate and still implements
`textView:completions:forPartialWordRange:indexOfSelectedItem:`. The method
discards the candidates supplied by AppKit and returns matching nv note titles.
The native `complete:` command can therefore still invoke nv-specific source
editing behavior.

This also exposes an accidental pass in the new regression suite. Its
completion check inserts one character and verifies that typing did not invoke
completion. It never requests completion, so it cannot detect a remaining
delegate provider.

Run:

```sh
python3 Tests/NativeEditingReview/round1/luu/run.py
```

The injected probe launched the Intel Development app with an isolated library
and passed six checks. It established that the active source editor delegates
to `AppController`, `Al` produces `Alpha Completion Candidate`, AppKit's input
candidate is replaced, and ordinary insertion remains `Alp`.

Remove the body-editor completion delegate method, or return AppKit's `words`
unchanged if a delegate implementation is still required. Extend
`Tests/SourceEditing` to call the delegate completion path and assert that nv
does not provide note titles.

## Validation limits

The probe calls the documented `NSTextViewDelegate` completion callback
directly. It does not automate the completion popup or keyboard layout. It
therefore proves the provider remains and that the current production test
misses it, but does not measure which physical key sequence invokes `complete:`
on every supported macOS version.
