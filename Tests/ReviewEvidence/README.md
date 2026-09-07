# PR review evidence

These files record three review rounds of the multiple-browser-window change. Each report identifies its reviewed commit, reproduction command, observed results, and limits.

The six AI perspectives use methods associated with John Ousterhout, Dan Luu, Linus Torvalds, and Kyle Kingsbury, plus compatibility and test skeptics. The named people did not participate.

## Reproduce a historical finding

Use the evidence commit below and build its Development app. Each evidence commit retains the reviewed production source and harness. Round 1 programs include assertions that confirm defects. They can fail after a fix, which does not indicate a new regression. Some runners read the integration harness from the checkout, so keep source, harness, and app revisions together.

| Round | Reviewed source | Evidence commit |
| --- | --- | --- |
| 1 | `30791c5` | `8e400d4` |
| 2 | `4008592` | `201c5f5` |
| 3 | `3502c7c` | `305629b` |

Reports preserve measured results. Timings depend on the machine; deterministic content and access-count assertions provide the stronger checks.

## Run current checks

Use the acceptance tests in `Tests/Regression/` for the corrected behavior, and run the main suite described in `Tests/README.md`. Review-only mutations operate on temporary source or copied apps.

GUI runners require macOS, an active desktop, and the documented Intel build. They use temporary libraries and separate preferences domains. They share `build/pr-review/gui.lock`; run only one GUI check at a time. Generated executables and raw logs stay outside the tracked evidence.
