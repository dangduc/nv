# Round 3: audit of evidence and claims

This contrarian review checks whether the stated validation matches saved evidence. It adds no runtime validation.

No new actionable discrepancy was found. The audit passes 73 artifact-consistency checks across 71 recorded inputs. Current production files match `c2209e2`. Their hashes remain unchanged at checkout `bfaebae`.

## Claims checked

| Claim | Saved evidence |
| --- | --- |
| Development build succeeds | The build log contains its success marker. |
| Copied-app regression passes 310 checks | `validation.json`, the result record, 310 native PASS lines, and the full-suite marker agree. The final wrapper log contains that native log. |
| HighlightBounds passes 134 checks | The final log and native, Intel, and sanitizer positive logs each contain the 134-check completion marker. |
| Eleven controls reach expected assertions | All eleven recorded control names and assertion lines match the corrected runner's map. Individual native logs contain the expected lines. |
| Sixteen runner unit tests pass | The saved output contains sixteen successful test lines, the sixteen-test summary, and `OK`. The manifest agrees. |
| Corrected runner code was tested | Both current runner hashes and the unit-test source hash match the correction manifest. |

The controls have eleven names. Two names share the same expected assertion text; the claim concerns eleven control outcomes, not eleven distinct assertions.

The current source runner clears the inherited first-case-only switch. Its success condition requires a zero exit and a complete suite marker. The bounds runner requires exit code one and its named assertion as an exact stderr line. This audit inspects those source conditions; it does not execute their branches.

## Review provenance

All twelve completed first- and second-round reports have manifests. Their production hashes match before and after their recorded runs. The saved result markers support the counts summarized in the review README.

Three initial reviews record the earlier editor hash: first-round Ousterhout, Luu, and Kingsbury. The other nine record the final production files. The README explains that distinction and warns that some historical scripts assert the presence of an old defect.

The simulated-process review remains identified as simulated evidence. The runner unit tests also retain their mocked-process scope. Their assertions are not counted as new app executions.

The original app's result record agrees with `validation.json`. The window comparison records 35 main checks and 11 relaunch checks before a signal. Its baseline record explicitly identifies the test-only early-cleanup bypass. The aggregate log contains the documented fuzzy-browser focus failure. The README and local PR draft do not present either full suite as passing.

## Wording and limits

The review README, suite README, and local PR draft preserve the macOS 13.7.8 limit. They state that the focused fixture supplies the search-background precondition and does not exercise search-field input. The review README distinguishes repeated assertion counts from independent user workflows.

Round-three work was still in progress during this audit. It was excluded from review-completeness checks. The README identifies that round as static evidence with no added native coverage. The separate ownership review's documentation clarification remains its own finding; this audit does not duplicate it.

The audit reads saved artifacts and source text. It cannot establish runtime behavior, authenticate historical logs, or prove coverage beyond the recorded fixtures. It reads the local PR draft only, not current GitHub text. It launches no application, native suite, or simulated process.

Run:

```sh
python3 Tests/SourceBackspaceReview/round3/contrarian-a/audit.py
```

`output.json` records each consistency check. `manifest.json` records the checkout, production hashes, and all input artifact hashes. The script writes review evidence only.
