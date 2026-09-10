# Org preview review — round 2, contrarian

No new actionable finding.
This review challenges the documented heading-link behavior with ordinary notebook text and ambiguous names.
It reviewed `415cf6920bd5c74bc3911829431f3dcff7c4acb2`, against base `f3a8abb2b7942d06ec33af64b4946cfd1b6db163`.

I wrote seven new fixtures and an independent semantic oracle in [run.py](run.py).
The oracle identifies target headings by document order.
It does not copy the converter's generated-anchor algorithm.
Expected visible text, explicit anchors, and unchanged file paths are fixture data.

The fixtures cover these choices from the [converter documentation](../../../../ThirdParty/OrgPreview/README.md):

- A first heading's `ID` competes with a later heading's `CUSTOM_ID`. The alias selects the first heading. The second heading remains reachable by its title.
- TODO state, priority, tags, and inline markup remain visible. Heading references match the documented raw title, including its markup.
- A Unicode ID contains a literal percent sequence, an ampersand, a quote, and a hash. Its encoded fragment resolves to the exact ID.
- A bare name matches a heading. Explicit file paths and web URLs retain their separate meaning, even beside identically named headings.
- Duplicate titles select the first heading. An explicit ID still selects the second heading.
- Example-block headings and links remain literal contents. They do not enter the heading index or produce active links.
- A later explicit ID reserves a name that otherwise resembles a generated anchor. CRLF source retains the same alias behavior as LF source.

The bundled helper and the unchanged production renderer each passed 69 semantic assertions, for 138 in total.
The [native harness](renderer.m) also passed 49 completion, snapshot-identity, and source-preservation checks.
The source checks compare UTF-8 bytes, including CRLF and combining characters.
Every fixture file retained its original hash.

Run the review from the preview worktree root:

```sh
python3 Tests/OrgPreviewReview/round2/contrarian/run.py
```

The command returned exit status 0.
[results.json](results.json) records every semantic assertion and its actual output.
[renderer-output.txt](renderer-output.txt) records the native checks.
[output.txt](output.txt) records the final command output.

The initial oracle compared serialized heading whitespace and URL spaces literally.
The renderer inserts HTML formatting whitespace and percent-encodes spaces in URLs.
Those differences preserve the expected visible text and path.
The final oracle compares collapsed heading whitespace and decoded path values.
It decodes fragments once, so literal percent sequences must still match the exact ID.
[oracle-initial-results.json](oracle-initial-results.json) and [oracle-initial-log.txt](oracle-initial-log.txt) preserve the initial diagnostic results.
No production correction followed those oracle changes.

The reviewed helper has 366,408 bytes and SHA-256 `dc5c563e75589ed615bc9faaad465f093ba180ac9c1b6baa3c4b2d874123fcba`.
The helper in the built app matches that artifact.
[metadata.json](metadata.json) records the helper, Rust adapter, renderer, snapshot, and fixture hashes.
The runner checked those production hashes before and after execution. They remained unchanged.
The commit also remained unchanged during the run.

These checks ran on macOS 26.5.2 with Xcode 26.6, using Intel code through Rosetta.
They do not establish live WebKit navigation, final pixels, source-editor Undo, or macOS 10.13 runtime behavior.
The separate provider-state finding and its correction are outside this review.
The stated unsupported features remain scope limits, including markup inside link descriptions and dedicated targets.
This review made no production edits or external posts.
