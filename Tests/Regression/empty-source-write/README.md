# Empty source writes

A note with an empty body is stored as a zero-length file. Foundation returns a NULL buffer
pointer for zero-length `NSData`, so once such a note is read back from disk and its source
baseline is cached, `-sourceDataReturningError:` used to hand that NULL pointer to
`FSRefWriteData`, which rejected it with `paramErr` (-50). The note then failed to save with
"Changed notes could not be saved because a parameter was invalid", and the temporary file
created for the atomic swap was orphaned in the notes directory.

The failure only appeared after a relaunch, because a freshly created note has no cached
source baseline, and it appeared for several notes at once during any pass that rewrites
every note, such as a storage-format change.

These checks cover:

- zero-length data exposes a NULL buffer pointer, and a zero-length file reads back that way
- `FSRefWriteData` accepts a zero-length write with a NULL buffer, and still rejects a NULL
  buffer with bytes to write, and a missing `FSRef`
- an empty-body note writes on creation, and rewrites after its source baseline is cached
- no orphaned temporary files remain in the notes directory

Run after a Development build, from an active desktop session:

```sh
python3 Tests/Regression/empty-source-write/run.py
```

Reverting either guard (`FSRefWriteData` in `Sources/Utilities/BufferUtils.c` or the
zero-length check in `-sourceDataReturningError:`) must fail these checks.
