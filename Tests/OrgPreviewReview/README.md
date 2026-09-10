# Org preview review record

[PR #18](https://github.com/dangduc/nv/pull/18) adds the Org viewer and its bundled converter.
Org source highlighting has a separate PR and review record.

The review uses five requested perspectives in two rounds.
These are agent reviews inspired by published priorities, without the named person's participation or endorsement.
Each reviewer writes and runs executable evidence. Reports identify their source snapshots and limits.

| Round | Perspective | Evidence | Published review |
| --- | --- | --- | --- |
| 1 | John Ousterhout | [Viewer boundaries and recovery](round1/ousterhout/report.md) | [Comment](https://github.com/dangduc/nv/pull/18#issuecomment-5611639610) |
| 1 | Dan Luu | [Conversion cost and cancellation](round1/luu/report.md) | [Comment](https://github.com/dangduc/nv/pull/18#issuecomment-5611576752) |
| 1 | Linus Torvalds | [Native packaging and rebuild](round1/torvalds/report.md) | [Comment](https://github.com/dangduc/nv/pull/18#issuecomment-5611719419) |
| 1 | Kyle Kingsbury | [Asynchronous publication and closure](round1/kingsbury/report.md) | [Comment](https://github.com/dangduc/nv/pull/18#issuecomment-5611597272) |
| 1 | Contrarian | [Ordinary notebook semantics](round1/contrarian/report.md) | [Comment](https://github.com/dangduc/nv/pull/18#issuecomment-5611608983) |
| 2 | John Ousterhout | [Public API and independent windows](round2/ousterhout/report.md) | [Comment](https://github.com/dangduc/nv/pull/18#issuecomment-5611845109) |
| 2 | Dan Luu | [Heading index and rendering cost](round2/luu/report.md) | [Comment](https://github.com/dangduc/nv/pull/18#issuecomment-5611787501) |
| 2 | Linus Torvalds | [Rebuild and artifact preservation](round2/torvalds/report.md) | [Comment](https://github.com/dangduc/nv/pull/18#issuecomment-5611820411) |
| 2 | Kyle Kingsbury | [Heading navigation and retained state](round2/kingsbury/report.md) | [Comment](https://github.com/dangduc/nv/pull/18#issuecomment-5611774368) |
| 2 | Contrarian | [Heading aliases and source semantics](round2/contrarian/report.md) | [Comment](https://github.com/dangduc/nv/pull/18#issuecomment-5611829264) |

## Findings

The first semantic review finds that ordinary starred and exact heading links become relative paths.
The converter correction resolves these references against the current document and emits matching fragment URLs.
[The unchanged review gate](round1/contrarian/fixed-output/report.md) passes all 24 semantic and 40 native checks after the correction.

The native review finds that direct Cargo invocation can silently produce an unstripped helper.
The rebuild script now supplies the toolchain library path and rejects failed stripping or remaining symbols.
[Rebuild validation](round1/torvalds/fixed-output/report.md) checks clean direct invocation and two failure cases.
Commit `415cf69` contains both first-round fixes.

The second state review finds that immediate capture after heading navigation rejects the current scroll position.
Commit `266b27e` ignores only the URL fragment when comparing document identity. The remaining identity and revision checks stay in place.
[Independent correction checks](round2/kingsbury/fix-validation.md) pass all 167 assertions, including the original failing capture.
The maintained copied-app suite passes 102 checks, including mismatched document identity and newer restoration state.

Both rounds are complete. All ten reviews are published, and all three findings are fixed.
Original failing evidence and later correction results remain separate.

## Validation limits

The host runs macOS 26.5.2 (25F84) with Xcode 26.6 (17F113).
The Intel Development app and helper run through Rosetta. Compilation targets macOS 10.13; no check ran on that operating system.
Each review report describes its native probes, substitutions, and measured boundaries.

The Development build passed before and after both rounds of corrections.
The corrected converter suite passed 45 checks, and the renderer suite passed 134 checks.
The final copied-app suite passed 102 checks. The earlier screenshot capture passed 59 checks.
The final executable has SHA-256 `b609ca3f9febb6e286a7e5a80c3e0521acebf5880f6c0dc90775512189e4126e`.
The bundled helper is 366,408 bytes with SHA-256 `dc5c563e75589ed615bc9faaad465f093ba180ac9c1b6baa3c4b2d874123fcba`.
The final helper, source hashes, architecture, deployment command, symbols, and linked library pass the verification script.

The required window suite reaches the previously recorded shared-text exception: index 13 with string length 12.
The aggregate suite reaches the previously recorded fuzzy-window activation failure.
These suites are not passing. Earlier records include [the User Scheme review](../UserSchemeReview/README.md).

The converter implements a documented Org subset. It does not evaluate code or expand includes.
Custom Emacs export settings, macros, footnotes, and agenda views are outside this pass.
