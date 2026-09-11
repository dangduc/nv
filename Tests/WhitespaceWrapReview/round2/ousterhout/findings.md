# Round 2: Ousterhout perspective

No actionable finding.
This review uses engineering priorities inspired by John Ousterhout. It does not represent his authorship or endorsement.

The frozen revision is `072a6bc0f54a52603f8cedfbcacc17d0ab836a36`.
The review focuses on the common paragraph policy in `GlobalPrefs.m` and its propagation through shared editing sessions.
The selected character-wrap policy intentionally permits visual breaks within words.

## Executed evidence

The new copied-app probe passed 42 checks.
It calls the real preferences, editors, editing sessions, snapshot history, and native paste import.
It does not replace the production methods or runtime paragraph policy.
The runner uses disposable notes, private preferences, and the shared GUI lock.

The checks establish these results:

- Repeated attribute requests and separate note sessions share one immutable paragraph object.
- A mutable client copy cannot change that common object.
- Two editors share the same live storage and retain the paragraph policy after native insertion.
- A font change retains the source and typing policy without a new source generation or modified date.
- Snapshot Undo and Redo preserve source characters and normalize snapshots to the current paragraph policy.
- Note switches preserve the peer's source and reuse the original shared storage on reattachment.
- An attributed external snapshot keeps its source characters and discards its old paragraph display metadata.
- That normalization leaves the caller's mutable paragraph object unchanged.
- Native text import from a private pasteboard retains the shared policy. Undo restores the prior source and policy.
- Four resize and glyph-regeneration cycles cause no storage notifications, source-generation changes, modified-date changes, or new pending edits.
- Those layout cycles also preserve source attributes and Undo/Redo availability.

The paste check uses `readSelectionFromPasteboard:type:` with a unique pasteboard.
It does not read or modify the user's general clipboard.
The external snapshot includes a word-wrap paragraph with custom line spacing and a different font.
The source session replaces those display attributes through its existing normalization path.

Host: macOS 26.5.2 (25F84), Intel app under Rosetta.
The executable SHA-256 is `be02dd1fe33a39c74b8961441be55f4f91378d46935bdba99fd610d405c3e09b`.

## Reproduce

From the worktree, run:

```sh
python3 Tests/WhitespaceWrapReview/round2/ousterhout/run.py
```

`results.json` records the exact executable and check count.
The full generated log is in `build/WhitespaceWrapReview/round2/ousterhout/candidate.log`.
The runner reuses the established copied-app launch helpers. The probe cases are new for this review.

The initial probe omitted a private BOOL method declaration.
The final probe declares the verified signature and passed all 42 checks without that compiler warning.

## Limits

This review covers plain-text paste import and an attributed external snapshot. It does not cover every RTF or HTML paste representation.
It does not establish frame timing, all input-method compositions, or behavior on macOS 13.
The synchronous layout checks do not cover every deferred callback or every application shutdown path.
