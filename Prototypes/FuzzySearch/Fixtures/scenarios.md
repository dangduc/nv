# Sample note queries

This corpus contains 40 fictional notes. It includes Markdown, HTML, JSON, Textile, plain text, and one 40 KB journal.
The journal contains repeated observation entries, followed by a distinct catalog key.

Use these queries to compare matches, excerpts, and the order from the native engine.
Other notes can also match short queries, particularly the long journal.

| Query | What to inspect |
| --- | --- |
| `mtg` | Compare the short “Meeting” note with “Monday meeting agenda” and “Mountain guide.” |
| `meeting` | Compare contiguous title matches with loose matches elsewhere in the corpus. |
| `nebula42` | Find “Field station log” through its body. Its title and tags omit this text. |
| `juniper` | Find “Garden plan” through its tags. Its title and body omit this text. |
| `copperlantern` | Compare “Trip packing” with “Workshop inventory.” The latter spreads the words across separate lines. |
| `copper lantern` | Compare the same notes with “Cabin supplies,” which reverses the word order. |
| `qzr` | Compare “Sequence A,” “Sequence B,” and “Sequence C.” Their bodies contain `qzr`, `qrz`, and `q\nz\nr`. |
| `silverfin` | Compare the HTML attribute in “Bookmark card” with “Silver fin.” |
| `requestID` | Find a JSON property in “Window settings.” |
| `opalbridge` | Find a JSON value inside the Markdown code block. |
| `amberfinch` / `violetotter` | Distinguish the two notes called “Release checklist” through their bodies. |
| `café` / `café` / `cafe` | Compare composed accents, decomposed accents, and unaccented text. |
| `Straße` / `strasse` | Compare the two route notes without assuming complete Unicode case folding. |
| `鴨川` / `小笼包` | Find Japanese and Chinese body text. |
| `🧑🏽‍💻` / `🧑‍🚀` / `🇨🇦` | Inspect highlights for emoji with modifiers and multiple code points. |
| `sync` / `syncronization` / `synchronisation` | Compare abbreviations, a missing letter, and different spellings. |
| `cobaltquartz` | Compare the short sample note with the final entry in the long journal. |
| `orchidmeteor` | Inspect a match across separated paragraphs in “Status memo.” |
| An empty query | Inspect all notes, including the empty “Untitled” note. |

The corpus preserves the original NFC and NFD encodings in its two accented café notes.
Equivalent Unicode display does not establish equivalent matching or correct highlight ranges.

The last `cobaltquartz` occurrence starts at byte 40,808 in the 40,876-byte journal body.
Its opening station label also contains those letters with spaces between them.
This case exposes the native engine's choice between an early loose match and a late contiguous match.

For asynchronous behavior, type `cobaltquartz` quickly, replace it with `nebula42`, then clear the field.
Check that the final rows and highlighted text belong to the current query.
If the prototype provides a stress corpus, repeat these steps with it.

The draft nvALT plan uses its own query grammar. This prototype can expose the native grammar for comparison.
If native extended syntax is enabled, compare `meeting` with `'meeting` for fuzzy and exact single-token matching.
An apostrophe starts that native exact token. Double quotes are not a substitute for it.
Do not infer final nvALT query behavior from native operators.
