# Round 1 corrections

Three implementation agents addressed the six published findings.

| Finding | Change | Acceptance evidence |
| --- | --- | --- |
| R1-01: metadata Undo routing | Store title and tag history in the note editing session's undo manager. Use a separate target to preserve metadata history across external body updates. | Native UI and metadata checks send responder Undo/Redo and check edit order, peer composition, deletion, closure, and deallocation. |
| R1-02: removed Search item | Restore Search before focusing it, including when the toolbar remains visible. | Native controls dispatch the Search menu action after removing the item. |
| R1-03: invisible disabled links | Fall back to the browser foreground when a link has no preferred foreground. | Native rendering checks typed URL pixels in two windows with opposite editor colors. |
| R1-04: empty-query Tab | Allow Tab to reach the body when a note is selected. | Native controls send Tab through the field editor, with and without a selection. |
| R1-05: library tag completion | Route header completion through the existing library tag provider. | Native controls check multiple tags, duplicates, and peer updates. |
| R1-06: appearance coverage | Remove the direct controller update from the appearance acceptance check. | Native UI checks rely on AppKit's automatic appearance callback. |

The controls and rendering probes also run against the preserved pre-correction app.
Each rejects the behavior it was added to detect.
See the acceptance directories under `Tests/Regression/` for commands and scope.

## Fixture corrections

The first completion fixture removed a tag before a peer tried to complete it.
The corrected fixture retains that tag and checks library membership before completion.

Sequential runs exposed inactive test windows before menu dispatch and rendering.
The fixtures now request native activation and assert readiness before those operations.
The rendering fixture also selects the explicit color scheme before setting custom colors.
Automatic appearance tests remain separate.
These fixture changes preserve the original behavior and pixel assertions.

## Validation

The combined Development build passed both required suites on macOS 13.7.8 with Xcode 15.2.
The regression suite includes 68 native UI checks, 84 control checks, and 438 rendering checks.
The multiwindow suite passed 35 checks and 13 relaunch checks.
The rendering run with artifact capture passed 486 checks, including 48 file-write assertions.

The preserved app produced zero white URL pixels with a black editor and disabled clickable URLs.
The corrected app produced 391 white URL pixels in the same case; ordinary text produced 112.
The negative control still fails the URL visibility assertion.

Full-screen transitions, live sync services, and external editor applications remain outside this validation.
The existing AppKit search-toolbar layout warning remains visible in these runs.
