Org preview review — round 2, contrarian

No new actionable finding at `415cf6920bd5c74bc3911829431f3dcff7c4acb2`.

I wrote seven ordinary-note fixtures and an independent oracle for the documented heading-link behavior.
Targets use expected heading positions rather than a copy of the generated-anchor algorithm.

All **138 semantic assertions** passed across the bundled helper and production renderer.
The native harness passed **49 completion and source-preservation checks**.
The fixtures cover competing CUSTOM_ID/ID aliases, raw markup in titles, duplicate headings, Unicode and literal-percent IDs, file/title ambiguity, example-block isolation, and CRLF.
The checks compare visible heading text, decoded targets, and unchanged UTF-8 source bytes.

Command: `python3 Tests/OrgPreviewReview/round2/contrarian/run.py` (exit 0).
Evidence: `Tests/OrgPreviewReview/round2/contrarian/`, including the executable probes, `report.md`, `results.json`, and `metadata.json`.

The reviewed helper is 366,408 bytes with SHA-256 `dc5c563e75589ed615bc9faaad465f093ba180ac9c1b6baa3c4b2d874123fcba`.
It matches the built app, and all compiled production inputs retained their hashes during the run.

The checks ran on macOS 26.5.2 / Xcode 26.6 with Intel code through Rosetta.
They exclude live WebKit navigation, provider state, final pixels, and complete Emacs export semantics.
Documented unsupported features remain scope limits.
