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

Two rounds use the requested Ousterhout, Luu, Torvalds, Kingsbury, and contrarian perspectives.
Each review includes executable evidence and states its validation limits.
Review reports and PR comment links will appear here as the rounds finish.
