# Round 1: pragmatic correctness and ownership review

Reviewed PR #24 at `b3c2162b9adea5e1c2819f7372ff0f7e7986a64a`, against `8dde5e8`.
Read `AGENTS.md`, `architecture.md`, and the production diff. No production files were changed.

No confirmed findings in this review scope. There is no severity, failing trigger, or recommended production fix to report.

## Executed evidence

Command:

```sh
python3 Tests/TypingReview/round1/torvalds/run.py
```

Environment: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), Intel target, manual reference counting, AddressSanitizer and UndefinedBehaviorSanitizer.
The runner compiles the complete production `NVSourceAnalysis.m` and extracts the actual link-decoration and percent-escape methods. It does not replace the scheduler or link parser with a model.

Results: exit 0, 3,854 checks passed, no sanitizer diagnostic.
See `artifacts/output.txt`, `artifacts/results.json`, and `artifacts/compile.log`.

| Probe | Trigger and coverage | Result |
| --- | --- | --- |
| Source ranges and empty input | 618 source/syntax cases, including empty strings, incomplete brackets, plain/Org syntax, emoji, combining marks, CJK, line breaks, and a deterministic generated corpus. Every emitted link is used to obtain its source substring. Counts are compared with Cocoa scripting words. | 1,591 link runs had nonempty ranges within the UTF-16 source and NSURL targets. Counts matched Cocoa. |
| MRC and queued cancellation | Hold one production worker at a bounded barrier, queue 40 other sessions, invalidate and close all 41 owners, and then release the worker. A surviving session first returns a nil snapshot, then requests empty-source analysis. | All 42 owners and delegates were destroyed on main. Canceled work drained without publication to destroyed delegates. The nil-snapshot request restarted and published empty links and zero words. |

## Code conclusions and limits

`NVSourceAnalysis.m:79-104` copies the snapshot and transfers only that copy and the ticket to dispatch blocks. `NVSourceAnalysis.m:115-122` clears the borrowed owner before releasing the ticket. The exercised cancellation and closure paths preserve those ownership boundaries.

`NVNoteEditingSession.m:206-228` rejects obsolete generation/syntax results and checks the remaining source length before each added link range. `NoteObject.m:138-140` supplies a nonnil supported syntax identifier, so the snapshot's plain-syntax fallback does not create a normal nil-syntax rejection loop.

`LinkingEditor.m:440` checks empty text before subtracting one from its length. The checks at lines 454 and 489 suppress stale direct link clicks and remove stale attributes before context-menu construction. These native action paths were reviewed, but were not executed by this headless probe.

The worker has no explicit exception recovery around Cocoa analysis. This probe did not produce an analysis exception from its valid strings and does not establish recovery from allocation failure or framework exceptions. No finding is asserted without a demonstrated ordinary failure trigger.

`NVSourceAnalysis.m:112-113` assumes its owner remains alive across the delegate callback. I found no application callback path that violates that assumption, so this is not a reported defect. A future delegate that synchronously releases the analysis owner would need a callback-lifetime guarantee.

The run did not launch nvALT, access personal notes, test open native menu actions, or validate UI responsiveness. System framework internals are not sanitizer-instrumented by this build.
