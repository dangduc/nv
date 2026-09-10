# Round 3 contrarian async review

No production defect emerged from this focused review. The actual Development app passed 39 checks.
The binary SHA-256 was `d2fc91aab87fbb3937073e11908832d177559761e46237ecd597a3bd9ca5ec80`.
The repository HEAD was `d93f93521beb4cd9f6e7d2ba77000eb2bcb41bd6`, with production changes through `5eda58b`.
The run used macOS 26.5.2 and Xcode 26.6.

The copied app used an isolated preferences domain, support directory, and library with twenty disposable notes.
The native editor received composed-character insertions with a 12 ms run-loop interval between calls.
Four phases covered short and 100,000-character sources in Plain Text and Org.
Each phase kept the word-count control visible and compared its final count with a separate Cocoa oracle.

| Phase | Original `words` calls | Original decorator calls | Calls on main | Calls on live storage |
| --- | ---: | ---: | ---: | ---: |
| Short Plain Text | 24 | 25 | 0 | 0 |
| Short Org | 24 | 24 | 0 | 0 |
| Long Plain Text | 1 | 23 | 0 | 0 |
| Long Org | 1 | 23 | 0 | 0 |

Observers recorded the original method entry, receiver identity, current thread, queue label, and return addresses.
Each observer forwarded the original implementation with unchanged arguments and return values.
All 145 calls used private objects on `org.nvalt.source-analysis`.
Every call contained a return address inside the actual production worker block.
The test derived the block range from the copied binary and adjusted it with the loaded helper address.
The editor and committed note retained every expected source character, including an emoji and a combining accent.
URL and wiki links retained their targets. Org web links retained their targets, and the Org file target remained inert.

The first sandboxed app process aborted before startup with exit status `-6` and no checks.
The desktop run required the same escalation as the other copied-app suites.
Two preliminary assertions incorrectly required a separate C helper frame. The optimized paths contained production worker frames and no separate helper frames.
The final assertion accepts the production worker frame and still requires private storage, the correct queue, and execution outside main.
These preliminary failures were harness limitations, not production defects.

The test observes actual application behavior during its four typing phases. It does not prove a universal absence of main-thread work.
The observer adds overhead, so this run supplies no latency measurement.
Programmatic native editor insertion does not reproduce physical held-key events or input-method composition.
The run supplies no evidence for macOS 13, disk reopen durability, or an uninstrumented app.
No production source changed. The test made no external link activation.

The reproducible command is `python3 Tests/TypingReview/round3/contrarian_async/run.py`.
The sources are `run.py`, `support.h`, and `probe-body.m` in this directory.
`output.txt`, `results.json`, `environment.json`, and `observations-summary.json` contain the recorded results.
Full observations and preliminary assertion logs remain under `build/TypingReview/round3/contrarian_async/`.
