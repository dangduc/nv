# Round 2 findings

No actionable finding was verified for the cleanup correction.
Both architectures passed the new callback, geometry, and sanitizer checks.

| Result | arm64 | x86_64 |
| --- | ---: | ---: |
| Behavior checks | 8,857 | 8,857 |
| Paragraph begins | 490 | 490 |
| Native paragraph ends | 490 | 490 |
| Cleanup calls during paragraph exit | 490 | 490 |
| Source-change sequences | 40 | 40 |
| Repeated cleanup cycles | 40 | 40 |
| ASan or UBSan diagnostics | 0 | 0 |

The JSON output check adds one successful check to each console total.
The early-cleanup negative control fails at check 5 with the expected callback-order assertion.

Production `Sources/Editor/NVSourceTypesetter.m:23` calls the native paragraph callback before cleanup at line 26.
The runtime wrapper observed that order in every paragraph exit.
The caches were empty after each completed callback.
The defensive cleanup at lines 15 and 135 remained safe after earlier cleanup.

Incremental snapshots matched fresh production layouts after source replacement, font edits, and width changes.
Finite containers exercised partially displayed paragraphs and continuation in later containers.
The fixtures also covered empty notes, blank paragraphs, and Unicode text.
These checks found no geometry change from the cleanup correction.

The attribute sentinel did not provide a valid ownership assertion.
The native Cocoa control released its marker after source replacement and pool drain.
The control that also created a Core Text line retained one marker after all explicit Core Text references were released.
That control does not link the nvALT typesetter.
The final suite therefore checks the production cache pointers directly and records the sentinel observation as a measurement limit.

The review ran on macOS 26.5.2 (25F84), with Xcode 26.6 (17F113).
The x86_64 run used Rosetta on the same host.
The sanitizers cover the compiled production implementation and harness, not the native framework internals.
The checks do not establish leak freedom, behavior after a native exception, or compatibility with older macOS versions.
The parent review owns the full application build and desktop suites.
