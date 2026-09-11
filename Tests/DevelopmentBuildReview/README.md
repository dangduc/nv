# Development build reviews

Each round uses six independent engineering perspectives inspired by the requested reviewers.
These are subagent reviews, not reviews by the named people.
Each reviewer writes and runs executable evidence against the recorded production commit.

| Round | Production commit | Status |
| --- | --- | --- |
| 1 | `2dbfd46` | Complete: two P2 findings corrected before round 2 |
| 2 | `3a3dc4f` | Complete: first custom-backup creation corrected before round 3 |

Review evidence stays in the corresponding round and perspective directory.
Production fixes follow the completed round, before the next round starts.

Round 1 found repeated bundle lookup during wiki-link scans and a copied-UUID collision under a shared custom backup root.
The scan now resolves its prefix once, when it finds its first link.
Development adds its own subfolder under a custom backup root.
The root checks passed 63 source-analysis checks, 2,060 Org-link checks, the backup coordinator suite, and the corrected nine-process destination fixture.
The active native-dependencies fixture now expects the current app's wiki-link scheme.

Ousterhout, Torvalds, UX, and platform reviews had no actionable findings.
The individual reports describe executable evidence and its limits.

Round 2 found that first use of a custom development backup folder failed before snapshot capture.
The coordinator now captures the selected parent's identity, rather than the absent namespace folder's identity.
The worker opens that parent and creates the fixed namespace and UUID children through directory descriptors.
It preserves the existing unavailable-root and replaced-root checks for publication, retention, and deletion.
The backup store passed 390 assertions, including fresh namespace creation and release-snapshot preservation during development deletion.
The backup coordinator suite also passed.
The other five perspectives found no additional actionable defect.
