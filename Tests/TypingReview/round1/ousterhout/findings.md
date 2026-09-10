# Round 1: analysis ownership and consumer interactions

Reviewed PR #24 at `b3c2162b9adea5e1c2819f7372ff0f7e7986a64a`, against `8dde5e8`.
Perspective: design complexity and state ownership, inspired by John Ousterhout's work.
This is an independent review, not a claim of his authorship or endorsement.

## Findings

No actionable findings in this review slice. No severity or production fix is proposed.

The session owns source generations, shared link state, and count subscribers.
The worker owns immutable snapshots and completion tickets. Canceled results cannot update the session.
The two probes below exercised the boundary between those responsibilities.

## Executed evidence

Command, from the worktree root:

```sh
python3 Tests/TypingReview/round1/ousterhout/run.py
```

Result: exit 0; **17 checks passed across two headless interleaving probes**.
The full output is in [output.txt](output.txt).

The runner compiles the production `NVSourceAnalysis.m` and extracts the production link decorator.
It also extracts the session methods at `NVNoteEditingSession.m:153–238` without logic changes.
The fixture replaces only the unrelated syntax highlighter with a no-op class.
Its text storage, layout managers, weak subscriber table, worker queue, and notifications use Cocoa.
It opens no application window and reads no user notes.

### Probe 1: subscribers change during a link job

Trigger: two layouts share a session. A link-only job pauses at a controlled worker barrier.
Both views request counts, then the first view cancels its request.
After publication, the second view detaches while the first layout remains attached.

Relevant source:

- `NVNoteEditingSession.m:175–190`: remove detached subscribers and schedule requested counts.
- `NVNoteEditingSession.m:196–204`: derive link and count work from current session state.
- `NVSourceAnalysis.m:60–69,107–115`: keep one pending request while a job runs.

Observed result: one word-only follow-up served the remaining subscriber.
The accepted count matched Cocoa's word rules. The accepted links matched the complete source snapshot.
After the interested view detached, a later edit refreshed links without computing another count.
No fix was needed for these sequences.

### Probe 2: last-layout detach, source change, syntax change, and reattachment

Trigger: a job pauses after a source edit. The last layout then detaches.
The source and syntax change while detached, and a new layout attaches before the old worker resumes.

Relevant source:

- `NVNoteEditingSession.m:153–183`: invalidate source and syntax work, and handle layout lifetime.
- `NVNoteEditingSession.m:206–237`: reject old generations and publish current links and counts.
- `NVSourceAnalysis.m:71–73,107–115`: suppress canceled jobs before delegate publication.

Observed result: the canceled job did not reach the delegate.
The replacement published the latest Org target and the final source's count.
A directly supplied obsolete generation also failed to alter either result.
Applying link attributes did not advance the source generation or cause another publication loop.
No fix was needed for these sequences.

## Limits

These probes cover session and worker behavior. They do not test native link menus, IME composition,
window presentation, or typing latency. The root review owns GUI validation.
No production files were changed, no commits were created, and no GitHub comments were posted.
