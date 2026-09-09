# Search toolbar review

The title bar contains one search field beside the native window controls.
The field expands with the window. The window hides its note title, and note commands remain available through menus.
A separate toolbar identifier prevents old saved layouts from restoring action icons.

## Validation before review

The Development Intel build passed on macOS 26.5.2 with Xcode 26.6.
The actual app opened, and the native UI checks passed search geometry at 480, 780, and 1,200 points.
Search focus, composition, clearing, note creation, title edits, and tag edits passed before the suite reached a shared-body Undo failure.

The full native UI and multiple-window suites failed during temporary-attribute invalidation after Undo shortened shared text.
An isolated build of the unchanged base, `66beeb9`, reproduced both exceptions with identical indices and string lengths.
Its file tree matches upstream `89d9abe`.
These failures predate the toolbar change.

| Suite | Result |
| --- | --- |
| Native UI | Toolbar and search checks passed. Later Undo raised index 16 outside string length 11 on both builds. |
| Multiple windows | Undo raised index 13 outside string length 12 on both builds. |
| Aggregate regressions | Native search suites passed. The copied-app fuzzy workflow stopped because its window did not become active. |

The [screenshot](../../docs/screenshots/titlebar-search.png) shows the actual Development app.

## Review rounds

[PR #10](https://github.com/dangduc/nv/pull/10) contains the implementation and review evidence.
The reviewers use the requested perspectives. Each report records its executable checks and limits.

| Round | Perspective | Report | PR comment |
| --- | --- | --- | --- |
| 1 | Ousterhout | [120 checks](round1/ousterhout/findings.md) | [Comment](https://github.com/dangduc/nv/pull/10#issuecomment-5606618618) |
| 1 | Luu | [21 geometry checks](round1/luu/findings.md) | [Comment](https://github.com/dangduc/nv/pull/10#issuecomment-5606623626) |
| 1 | Torvalds | [54 checks and availability control](round1/torvalds/findings.md) | [Comment](https://github.com/dangduc/nv/pull/10#issuecomment-5606629410) |
| 1 | Kingsbury | [354 checks across two launches](round1/kingsbury/findings.md) | [Comment](https://github.com/dangduc/nv/pull/10#issuecomment-5606686129) |
| 1 | Contrarian | [38 checks](round1/contrarian/findings.md) | [Comment](https://github.com/dangduc/nv/pull/10#issuecomment-5606691698) |
| 2 | Ousterhout | [168 checks and native teardown](round2/ousterhout/findings.md) | [Comment](https://github.com/dangduc/nv/pull/10#issuecomment-5606822352) |
| 2 | Luu | [746 checks in Source and Preview](round2/luu/findings.md) | [Comment](https://github.com/dangduc/nv/pull/10#issuecomment-5606824848) |
| 2 | Torvalds | [196 compatibility and recovery checks](round2/torvalds/findings.md) | [Comment](https://github.com/dangduc/nv/pull/10#issuecomment-5606883276) |
| 2 | Kingsbury | [107 checks across four asynchronous histories](round2/kingsbury/findings.md) | [Comment](https://github.com/dangduc/nv/pull/10#issuecomment-5606887906) |
| 2 | Contrarian | [48 checks across three windows](round2/contrarian/findings.md) | [Comment](https://github.com/dangduc/nv/pull/10#issuecomment-5606827350) |

The [round-one response](round1/response.md) records the disposition of each review.
No first-round review requested a production correction.
The delegated runner correction removed its dependency on a private build-log filename.
The [round-two response](round2/response.md) records native lifecycle, geometry, restoration, asynchronous state, and accessibility results.
Both rounds are complete. All ten review comments link to executable evidence.
No actionable production finding remains from either round.
