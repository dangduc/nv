# Round 3: browser projection consistency

Reviewed HEAD: `d93f93521beb4cd9f6e7d2ba77000eb2bcb41bd6`. Production revision: `5eda58bd50bdda6b31ea705ad1ce6b256ffd671a`. PR #24 base: `8dde5e8`.
This review uses a Kyle Kingsbury-inspired perspective. Kyle Kingsbury did not perform this review.

No new actionable defect appeared in this bounded matrix.

`python3 Tests/TypingReview/round3/kingsbury/run.py` passed **1,389 checks across eight event orders and 48 browser histories**.
The native probe used AddressSanitizer and UndefinedBehaviorSanitizer. Both reported no error. The runner disabled leak detection.

Each event order starts six independent browser sessions over one memory library and one production search service.
The sessions include empty queries, Exact queries, Fuzzy queries, and reverse Date Modified sorting.
The probe first blocks library publication through the delegate and queues two body edits in each empty-query session.
It then changes the order of these events:

- A title change and a tag change update the committed search snapshots.
- A deletion removes a note. A new note receives the same title and a different UUID.
- Query changes cross from empty to active and from active to empty. A Fuzzy query also changes and returns to its original value.
- Body edits change membership and date order. Two edits restore the original body of another note.

The main run loop processes deferred work between events. Active queries reject row actions immediately after body edits.
Metadata and deletion invalidation also reject row actions before replacement publication.

After publication resumes, each browser reaches current results. A separate search service receives fresh snapshots from the final library.
A new browser session supplies the comparison result for each query, search mode, and sort order.
Every history matches this fresh projection for visible object identity, occurrence keys, row order, result counts, and distinct note counts.
Every occurrence key resolves to its current row. Commands over all rows resolve exactly the unique current notes.
Deleted objects remain absent, including after the delayed body work drains.

`results.json` records source hashes, compilation commands, the reviewed HEAD, and the native exit code.
`output.txt` records every assertion. Generated objects, the binary, and compiler output are under `build/TypingReview/round3/kingsbury/`.

Limits: This headless probe compiles the full production browser session, query parser, search corpus, search service, and native Fuzzy engine.
Memory fixtures replace the note model, library, preferences, and browser delegate. The probe calls model notification entry points directly.
It does not cover AppController selection, retained editor rows, GUI interactions, storage, Undo, or notification delivery from real editing sessions.
The fresh oracle uses the same production projection algorithm. It detects history-dependent errors but cannot exclude an algorithm error shared by both paths.
Eight event orders do not cover every possible event order. This review made no production changes.
