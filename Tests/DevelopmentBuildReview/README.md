# Development build reviews

Each round uses six independent engineering perspectives inspired by the requested reviewers.
These are subagent reviews, not reviews by the named people.
Each reviewer writes and runs executable evidence against the recorded production commit.

| Round | Production commit | Status |
| --- | --- | --- |
| 1 | `2dbfd46` | Complete: two P2 findings corrected before round 2 |
| 2 | `3a3dc4f` | Complete: first custom-backup creation corrected before round 3 |
| 3 | `47d18f4` | Complete: selected-parent canonicalization corrected after review |

Review evidence stays in the corresponding round and perspective directory.
Production fixes follow the completed round, before the next round starts.
Some runners require the source checkout and built products at their recorded commit.
Later fixes can invalidate those historical checks.

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

Round 3 found that custom-root canonicalization included the Development namespace before the coordinator captured the selected parent's identity.
The coordinator now canonicalizes only the selected parent, then appends the namespace.
The worker retains responsibility for validating and opening that child.
This finding follows source data flow; the review did not create a redirection fixture.

The other five perspectives found no additional actionable defect:

- Ousterhout: 252 assertions in concurrent complete apps, including first manual and automatic custom backups and payload checks after relaunch.
- Luu: namespace creation stayed on the serial worker while the main run loop continued; existing destinations added one child open and close.
- Kingsbury: 169 checks across five reopened store processes preserved peer snapshots through publication, retention, and deletion.
- Contrarian UX: 74 assertions across ten processes preserved release settings and browser records through Development changes and reset.
- Contrarian platform: 444 native assertions rejected absent or stale selected roots before creating a namespace.

Torvalds also ran 1,603 descriptor assertions per architecture, with no descriptor-lifecycle finding.
Each report records its fixture boundaries and runtime limits.

The final source correction is `9a69037`.
Torvalds verified the corrected parent derivation from source.
Both rebuilt apps passed the complete-app custom-backup runner again, with all 252 assertions passing.
The backup store passed 390 assertions, and the coordinator suite passed.
See the [validation record](../DevelopmentBuild/VALIDATION.md) for build checks and the existing aggregate-suite limits.
