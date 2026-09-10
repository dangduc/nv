### Round 1 — contrarian review

**[P2] Resolve heading links within the current document** — `ThirdParty/OrgPreview/src/main.rs:59–61`.

The link handler copies Org heading targets directly into HTML URLs.
For a heading with `CUSTOM_ID: release-plan`, `[[#release-plan][By custom ID]]` works.
However, `[[*Release plan][By heading]]` emits `href="*Release plan"`, and `[[Release plan][By exact heading]]` emits `href="Release plan"`.
Both targets are relative paths without fragments, so they cannot navigate to the existing heading anchor.
The production renderer retains them unchanged.

These are standard in-document links, independent of custom export settings. [Org manual: Internal Links](https://orgmode.org/manual/Internal-Links.html).
Resolve supported heading references against the document and emit matching fragment URLs.
This prevents ordinary notebook tables of contents from mixing working custom-ID links with broken heading links.

Evidence at `Tests/OrgPreviewReview/round1/contrarian/` uses the actual helper and production renderer on ten ordinary fixtures.
Twenty of 24 semantic checks pass. Four fail for the two heading-link forms across both output paths.
All 40 native completion/source-preservation checks pass.
The runner intentionally exits 1 for the recorded semantic failures.

The report also records literal handling of explicit list counters, description lists, and styled link descriptions as scope limits.
The checks do not click a live WebKit view or claim complete Org export coverage.
