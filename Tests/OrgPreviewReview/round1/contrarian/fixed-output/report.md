# Internal heading-link fix

The helper now indexes headings before export. Starred and exact heading references resolve to same-document fragments.
Each heading receives a unique anchor. Explicit CUSTOM_ID and ID values supply anchors or aliases.
Duplicate titles and IDs select the first matching heading. Generated anchors avoid all explicit heading IDs, including later headings.
Unicode and punctuation in fragment targets use percent encoding. External and explicit file links retain their previous targets.

The unchanged round-one runner passes all 24 expected-output checks and 40 native renderer checks with the fixed helper.
The initial 20/24 result remains in the parent directory. The runner and native probe were copied without changes to an isolated tree.
That tree used the production renderer sources and a minimal NSBundle containing the fixed helper.
[replay.json](replay.json) records the probe hashes and the preserved initial evidence hashes.
[metadata.json](metadata.json) identifies the tested helper and source hashes. Its HEAD identifies the base commit; the fix was uncommitted.

The maintained helper suite passes 45 checks, including 18 new heading and link checks.
The maintained native renderer suite passes 134 checks, including fragment preservation through the document sanitizer.
Native WK navigation is assessed separately in the second review round.

The bundled helper is 366,408 bytes with SHA-256 `dc5c563e75589ed615bc9faaad465f093ba180ac9c1b6baa3c4b2d874123fcba`.
The source hashes and binary metadata pass `Scripts/rebuild-org-preview.py --verify-only`.
