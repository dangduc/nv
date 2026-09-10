### Round 2 — native correctness

Linus Torvalds-inspired review perspective; this does not represent his views.
Reviewed immutable snapshot `415cf6920bd5c74bc3911829431f3dcff7c4acb2`.

**No new actionable findings.** The first-round direct-Cargo finding is fixed. A fresh offline rebuild with an empty Cargo cache and no caller `DYLD_` variables produces the stripped 366,408-byte helper. It matches the checked-in artifact after masking only its Mach-O UUID.

I wrote **68 new checks**. The production inspector rejects a real unstripped Intel executable. Simulated strip warnings and Cargo errors are rejected before artifact copy, preserving existing output and manifest bytes. A real read-only destination failure preserves those bytes too.

Five new heading fixtures pass 25 conversions. They cover Unicode titles, explicit IDs and aliases, ID collisions, LF/CRLF, missing final newline, and deep headings. One-, two-, five-, and thirteen-byte pipe writes produce identical output, including valid links to generated anchors and balanced heading tags.

Actual macOS 10.13 execution remains untested. The copy check covers failure before the destination opens, not interrupted partial writes. Native HTML checks do not prove WebKit navigation or the concurrent preview-controller change.

Evidence: `Tests/OrgPreviewReview/round2/torvalds/report.md`, `run.py`, and recorded output/metadata.
