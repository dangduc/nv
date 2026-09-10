Round 2, contrarian A: evidence validity and test reliability.

The review found two test-reliability issues. Neither finding changes the recorded result that the fixed app passed 310 native checks. Both findings concern future results that the runners can accept without the intended evidence.

[P2] The normal backspace runner can inherit the first-case-only switch.

`Tests/SourceBackspace/run.py` copies the parent environment into the child environment. It sets `NV_BACKSPACE_REPRO_ONLY` for the negative control but does not remove an inherited value for normal runs. The native fixture reads this variable and exits after the first case. Its early completion message also contains `SOURCE BACKSPACE PASSED`, which satisfies the normal success predicate.

The controlled runner experiment supplied the actual early completion message and 12 simulated checks. The normal runner returned success and wrote `passed: true` in `production-regression` mode. This path skips the remaining syntax, Undo, composition, and lifecycle coverage.

Remove the inherited switch before the runner selects its mode. Require a completion marker that identifies the full suite.

[P2] The highlight mutation runner accepts unrelated child failures as expected rejections.

`Tests/FuzzySearch/HighlightBounds/run.py` accepts every nonzero exit for a mutation case. The extracted `run_case` function accepted a simulated loader failure with exit 127. It also accepted a simulated signal with exit -11. Neither result contained the expected assertion, yet the function printed `REJECTED` and returned normally.

Require the expected assertion and exit code for each mutation. Reject loader failures, signals, and unrelated assertions.

The saved native mutation logs contain the intended assertion failures. The second finding therefore does not invalidate those recorded runs. It identifies a gap in the decision that classifies later mutation results.

The new runner experiment completed 21 checks. It also exercised the original-crash signature, wrong indices, unrelated exceptions, successful deletion, timeout, application copying, and aggregate failure propagation. The aggregate runs SourceBackspace first and stops after a child failure. It does not print its final success marker after that failure.

The experiment ran maintained Python control flow with simulated compiler and application subprocesses. The fake application file was never executable. It did not launch nvALT, reproduce an AppKit exception, or run a native editor check. The experiment establishes runner decisions for the supplied child results.

`manifest.json` records the historical reviewed commit and unchanged hashes for four production files and nine test files. `output.txt` contains all 21 checks and the controlled result records. The review files remain separate from the maintained runners.

Evidence command:

```sh
python3 Tests/SourceBackspaceReview/round2/contrarian-a/run.py
```
