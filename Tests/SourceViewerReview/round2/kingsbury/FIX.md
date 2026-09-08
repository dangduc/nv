# Round 2 storage corrections

Addressed PR #4 comments:

- [Deleted-note conversion completion](https://github.com/fastducduc/nv/pull/4#discussion_r3956536859).
- [Repeated conflict copies after synchronization failure](https://github.com/fastducduc/nv/pull/4#discussion_r3956536868).
- [UTF-8 transport BOM and literal U+FEFF](https://github.com/fastducduc/nv/pull/4#discussion_r3956584009).

## Changes

Conversion requests now have distinct identities and check the exact live library note at scheduling, presentation, and completion.
Note removal cancels queued presentation and invalidates the request. An open sheet's old completion cannot act on deletion Undo or a replacement note.
Live database notes can still request conversion after source export fails, even when no plain-file conversion is pending.

Conflict copies archive their origin note UUID inside the note data. Retries reuse a copy with the same origin, bytes, and encoding.
A changed conflict file is preserved separately. Failed file or journal operations do not advance the original source baseline.
Reused copies still need a synchronized journal record before the original source can be replaced.
Encoding comparisons accommodate the signed 32-bit encoding identifiers in legacy note archives.

UTF-8 decoding gives Foundation the complete BOM-bearing data. Foundation removes the transport BOM once and preserves a following literal source U+FEFF.
The explicit UTF-16 and UTF-32 decoding paths retain their existing BOM handling.

## Regression evidence

```sh
python3 Tests/Regression/source-storage/run.py
```

The suite retains the existing source storage coverage and adds:

- Deletion before sheet presentation, deletion while its completion is pending, a new note at the same filename, and deletion Undo.
- Successful conversion and exact export from a live database note with no pending source-file write.
- Three failed synchronization attempts, one copy per external version, a second version with UTF-16 encoding, archive recovery, and successful conversion.
- A real journal recovery read before the original source write, including when the conflict copy is reused.
- BOM-only source, transport BOM plus literal U+FEFF, unchanged bytes, and edited bytes for UTF-8, UTF-16 LE/BE, and UTF-32 LE/BE.

The final rebuilt suite passed **235 checks** with exit 0 on macOS 26.5.2 under Rosetta.
The output is recorded in `build/source-storage-round2-fix.log`.
A prior archive-identity check failed against the previous app at the new encoding comparison.
The failure established that the fixture detects the signed encoding identifier before directory reconciliation normalizes it.
Clang syntax checks pass for all three changed implementations. The combined Development build and `git diff --check` pass.

The failure injection returns `NO` at the WAL synchronization boundary. It does not simulate kernel failure or power loss.
All app runs use copied applications and disposable libraries. Historical review probes and reports remain unchanged.
