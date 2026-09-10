**Resolved: round 2 heading-scroll capture finding.**

I inspected the fragment-only document comparison and independently reran the unchanged reviewer gate: **167 checks passed**.
The previously failing starred link now captures **2,540 pixels**, the actual heading position.
All seven immediate captures pass, including Unicode fragments after source replacement.
The existing navigation, independent window state, and displayed-document export checks also pass.

The fix retains the other document and presentation identity checks.
Evidence: `Tests/OrgPreviewReview/round2/kingsbury/{verified-output.txt,verified-metadata.json,fix-validation.md}`.
Provider SHA-256: `e786f468b82d7ae45c59adb3aed5123bcaa6dc3b757145ead9b219e90b79436a`.
Production inputs and the reviewer gate remained unchanged during the run.
The original failure and author's fixed-run artifacts remain preserved.
