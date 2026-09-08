# Source syntax flicker review

PR: [Keep source syntax colors visible while typing](https://github.com/fastducduc/nv/pull/6).
Base: `8cd2c9591041b8cdef367c6a0f78304e00192a45`.
Production fix: `65e1608ff4e9977ec2d7a09297739152f9cfc935`.

The named perspectives are analytical styles inspired by the requested reviewers. Those people did not participate or endorse these reviews.
Each review includes native executable evidence and recorded output. Reports distinguish confirmed defects from fixture errors and untested behavior.

## Round 1

No confirmed actionable introduced defect was found in these five reviews. No production fix was assigned from this round.

| Perspective | Executed scope | Report |
| --- | --- | --- |
| John Ousterhout-inspired design | 12 attachment histories, blocked completion after close, actual owner/parser release; 200 checks and a contract mutation | [Report](round1/ousterhout/REPORT.md) |
| Dan Luu-inspired performance | Two 120-edit bursts with one/four layouts, capture-write and coalesced color-run counts, exact display-budget boundaries | [Report](round1/dan_luu/REPORT.md) |
| Linus Torvalds-inspired correctness | 72 edit histories across three syntaxes and two laid-out containers, 54 final-display comparisons, retained-display mutation | [Report](round1/linus/REPORT.md) |
| Kyle Kingsbury-inspired state histories | Ten gated worker histories, stale positive/empty/nil results, syntax changes, closure, storage migration; 161 assertions and a generation-fence mutation | [Report](round1/kingsbury/REPORT.md) |
| Contrarian integration | Six syntax/appearance histories in two editors, link/search/marked-text precedence and Undo/Redo; 109 checks and a baseline failure control | [Report](round1/contrarian/REPORT.md) |

The performance probe initially confused raw TextKit segments with distinct color runs. Its final counters merge adjacent equal capture values.
The integration probe initially installed search backgrounds without a search query. Both the previous and fixed apps remove those backgrounds after typing.
The reports retain the failed fixtures, corrections, and controls. Neither observation established an introduced defect.

## Validation and reproduction

The production fix passed an Intel Development build on macOS 26.5.2 (25F84), Xcode 26.6 (17F113).
The multiple-window suite passed 35 checks, with 13 more after relaunch. All 18 regression suites passed.
These include 409 source-highlighting checks and 189 native source-workflow checks.
The [CI build for the production fix](https://github.com/fastducduc/nv/actions/runs/34225336321) also passed.

[The screenshot probe](visual/README.md) compares the same pending-parser state in the previous and fixed apps.
It holds analysis for a stable native screenshot. It does not measure the normal flicker's duration.

[run-parser-probe.py](run-parser-probe.py) compiles each standalone review probe with the production highlighter and pinned grammars.
Each report gives its reproduction command. Build outputs use a separate directory for each review.
GUI probes use the shared lock, copied apps, separate preferences, and disposable notes through `Tests/ViewControlsReview/run-probe.py`.
The review evidence does not establish physical IME behavior, all macOS versions, or exhaustive scheduling and latency bounds.
