# Org source review record

[PR #17](https://github.com/dangduc/nv/pull/17) adds Org source syntax and file import support.
The preview implementation has a separate PR and review record.

Two rounds use five requested review perspectives. These are agent reviews inspired by each person's published priorities, without their participation or endorsement.
Each reviewer wrote and ran executable evidence. Each directory contains its report, probe source, output, and source snapshot.

| Round | Perspective | Evidence | Published review |
| --- | --- | --- | --- |
| 1 | John Ousterhout | [Ownership and shared editing](round1/ousterhout/report.md) | [Comment](https://github.com/dangduc/nv/pull/17#issuecomment-5611347927) |
| 1 | Dan Luu | [Parser and link cost](round1/luu/report.md) | [Comment](https://github.com/dangduc/nv/pull/17#issuecomment-5611362029) |
| 1 | Linus Torvalds | [Native correctness and packaging](round1/torvalds/report.md) | [Comment](https://github.com/dangduc/nv/pull/17#issuecomment-5611374631) |
| 1 | Kyle Kingsbury | [State publication and closure](round1/kingsbury/report.md) | [Comment](https://github.com/dangduc/nv/pull/17#issuecomment-5611429144) |
| 1 | Contrarian | [Ordinary note semantics](round1/contrarian/report.md) | [Comment](https://github.com/dangduc/nv/pull/17#issuecomment-5611455330) |
| 2 | John Ousterhout | [Public API and lazy metadata](round2/ousterhout/report.md) | [Comment](https://github.com/dangduc/nv/pull/17#issuecomment-5611518381) |
| 2 | Dan Luu | [Typing cost and display limits](round2/luu/report.md) | [Comment](https://github.com/dangduc/nv/pull/17#issuecomment-5611532994) |
| 2 | Linus Torvalds | [Scanner codec and session isolation](round2/torvalds/report.md) | [Comment](https://github.com/dangduc/nv/pull/17#issuecomment-5611526219) |
| 2 | Kyle Kingsbury | [Fallback and peer recovery](round2/kingsbury/report.md) | [Comment](https://github.com/dangduc/nv/pull/17#issuecomment-5611558143) |
| 2 | Contrarian | [Delimiter and newline semantics](round2/contrarian/report.md) | [Comment](https://github.com/dangduc/nv/pull/17#issuecomment-5611569023) |

## Findings

- Round 1 performance: commit `e7e1c93` caches each line boundary during Org link decoration. The maintained link suite rejects the original implementation.
- Round 1 native correctness: commit `a773c6a` validates the complete scanner representation before encoding or restoring it. Failed scanner state selects plain source.
- Round 1 semantics: commit `4dab02a` classifies each comment line and retains emphasis in hashtag prose.
- Round 2 semantics: commit `85a48cb` fixes unmatched-literal suppression, CRLF span failure, and the closing boundary before an explicit line break.
  [The fix report](../OrgSource/round2-fixes.md) records the maintained regression cases and three negative controls.

Original findings and failing output remain in the review directories. Fix validation uses separate output files.

## Final source validation

The Development build passed after commit `85a48cb`.
The executable has SHA-256 `a68ed29583d90a18dc2ba38f0146a92d6ff1254373c68ab7193c7a330714f4f7`.
The maintained Org suite passed 864 checks and dependency hashes. The link suite passed 2,060 checks.
The copied-app integration suite passed. The unchanged second-round semantic gate passed all 23 fixtures, 377 mechanical checks, and 38 edited-link checks.
The final required desktop suite results retain the failures described below.

## Validation limits

The host runs macOS 26.5.2 (25F84) with Xcode 26.6 (17F113). Intel app tests run through Rosetta.
Compilation targets macOS 10.13. No check ran on that operating system.
The native scanner checks also run on arm64, with ASan and UBSan.

The required window suite reaches the previously recorded shared-text exception: index 13 with string length 12.
The aggregate suite reaches the previously recorded fuzzy-window activation failure.
These suites are not passing. Earlier records include [the User Scheme review](../UserSchemeReview/README.md).

The round 1 ownership probe also records visible-editor Undo failures for both Org and Plain Text with the same Unicode edit.
That control did not run against a baseline binary. Passing detached-editor checks do not establish visible-editor Undo correctness.
Large notes and dense paragraphs retain the documented parser, display, and synchronous link-decoration limits.
