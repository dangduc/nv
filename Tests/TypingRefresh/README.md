# Typing refresh regression checks

Run the production app with temporary notes, separate preferences, and read-only method counters:

```sh
python3 Tests/TypingRefresh/run.py
```

Build the Development app first. Use `--app` to select another build, or `--compile-only` to compile without opening an app.
The runner copies the app and uses the shared desktop-test lock.
It does not change the user's notes or preferences.

The checks cover:

- Synchronous body commits with no full-list or header refresh for each key.
- One content notification per source window, including shared storage and Undo.
- Preview invalidation for the changed note only.
- Periodic dirty-row delivery during typing and final delivery after typing stops.
- Date Modified sorting with the selected occurrence preserved.
- Immediate invalidation for Exact and Fuzzy searches, including duplicate occurrences.
- Highlight removal when the query becomes empty.
- Shared marked text, deferred model commits, and commit after composition ends.
- Cancellation when a browser detaches, and deletion while a row refresh is pending.
- A final library checkpoint.

The injected methods count calls and then invoke the production implementation.
They do not skip editing, rendering, search, or persistence work.
The report and native log are saved in `build/TypingRefresh/`.
These checks establish behavior; they do not measure presented frames or reproduce macOS 13 stutter.
