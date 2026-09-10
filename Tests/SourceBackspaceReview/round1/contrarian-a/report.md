Round 1, contrarian A: challenge added complexity and the causal claim.

No actionable finding. The added state protects separate operations at separate times. The evidence does not support a smaller change that removes these protections.

The review uses five extracted editor methods and the exact character observer. The probe uses native `NSTextStorage`, `NSLayoutManager`, notifications, and timers. It does not create a window or replace production source files. The manifest records the base, reviewed commit, and four unchanged production hashes.

The production methods pass 16 checks on macOS 26.5.2. Five altered variants each fail the intended assertion. The runner rejects unrelated exceptions and process failures as control evidence.

| Removed protection | Observed consequence |
| --- | --- |
| Immediate background suppression | TextKit retains the old background until cleanup. The draw delegate then returns that stale background. |
| Cancellation before fresh publication | The old callback removes the new search background. |
| Character-edit guard | An explicit clear mutates native temporary attributes inside an open edit transaction. |
| Immediate generation advance | The old async generation remains valid after the character change. |
| Cleanup before storage detachment | The old callback runs against the replacement storage. |

The final control concerns ownership. That control does not establish a visible error or data loss by itself. The pre-detach call enforces the documented boundary with one existing method.

An additional control restores both original methods from `54ce3b8`. Four checks pass with an uncached layout. The original observer clears the background during character processing, but this small fixture does not crash. Character deletion alone therefore does not establish the AppKit exception. The copied-app regression supplies evidence for the cached-window failure.

The review covers stale presentation, fresh publication, nested edit transactions, generation invalidation, and storage replacement. It does not cover bitmap drawing, IME pixels, real browser sessions, or the reported macOS 13.7.8 environment. The probe has no latency assertions.

The command is:

```sh
python3 Tests/SourceBackspaceReview/round1/contrarian-a/run.py
```

`output.txt` contains the results. `manifest.json` contains the source hashes and platform. `build/BackspaceReview/round1/contrarian-a/` contains generated sources, binaries, and individual logs.
