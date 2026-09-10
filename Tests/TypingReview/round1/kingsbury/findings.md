# Round 1: publication and lifecycle consistency

Reviewed PR #24 at `b3c2162b9adea5e1c2819f7372ff0f7e7986a64a`, against `8dde5e8`.
Perspective: consistency and controlled scheduling, inspired by Kyle Kingsbury's work.
This review is not his work or endorsement.

## P2: Resume Reveal after invalidating an Exact projection

**Changed line:** `Sources/Browser/NVBrowserSession.m:207` (`resultsCurrent = NO`).

**Trigger:** A background browser has an Exact query. A newly added note matches
that query. The model hook invalidates the browser and schedules a list refresh.
`revealNote:options:` runs before that refresh.

The new invalidation state sends Reveal into its pending-intent branch at
`Sources/Browser/AppController.m:1641–1644`. This bypasses the existing synchronous
Exact refilter at line 1653. The later Exact publication sets `resultsCurrent`
back to YES at `NVBrowserSession.m:486`, but only sends a state-change callback
at line 493. It never sends `browserSessionSearchDidComplete:`. That completion
callback is the consumer of `pendingSearchReveal` in
`Sources/Browser/AppController_Search.m:80–95`; the state-change callback at
lines 62–79 does not consume it.

**Observed impact:** The requested note becomes present in a current projection,
but remains unselected. Its Reveal intent remains pending after the run loop
drains. This is a lost command, not only a change from synchronous selection to
asynchronous selection. The baseline selects the note immediately and retains
the matching query.

**Fix:** Preserve the new protection against stale row actions. Before the
pending-result guard, allow an explicit Reveal to refresh a synchronous Exact
projection when composition does not prevent publication. Alternatively, make
synchronous publication complete pending selection intents too, while guarding
against recursive publication. The equivalent empty-query path also merits a
regression check because it uses synchronous publication.

## Executed evidence

Run from the worktree root:

```sh
python3 Tests/TypingReview/round1/kingsbury/run.py
python3 Tests/TypingReview/round1/kingsbury/run.py --baseline-reveal
```

Both commands exited 0. Candidate: **23 assertions**, including two assertions
that deliberately confirm the regression. Baseline: **4 assertions**, confirming
the prior successful selection. See `candidate-output.txt`, `baseline-output.txt`,
and their matching result JSON files. A zero exit for the candidate means the
regression was reproduced as specified; it does not mean the candidate is correct.

The runner compiles the complete production `NVBrowserSession.m`, search service,
and native search code. It extracts the complete production
`AppController.revealNote:options:` method without changes. In-memory note,
library, and view doubles supply the surrounding protocol. The delegate records
completion callbacks; the candidate receives none after the Exact refresh.
For the baseline run, only `NVBrowserSession.m` comes from `8dde5e8`; the Reveal
method is unchanged between those revisions. No desktop or user library opens.

The root review independently reproduced the same trigger in the actual app:

```sh
python3 Tests/Regression/editing/run-probes.py
```

Candidate log: `build/TypingValidation/Tests_Regression_editing_run-probes.py.log`.
It fails at `Tests/Regression/editing/probes.m:169–170`, after confirming the new
note is absent from the background browser's old projection.
Baseline log: `build/TypingValidationBaseline/Tests_Regression_editing_run-probes.py.log`.
It passes that assertion and finishes all **52 checks**. These GUI runs belong
to the root review; this reviewer read their results and did not launch them.

## Other controlled interleavings

The remaining **19 candidate assertions passed**:

- An inline editor blocks row publication while two dirty UUIDs accumulate.
  Unblocking delivers both rows once and keeps empty-query membership actionable.
- A deletion invalidates membership while row publication is blocked. Body work
  queued both before and after invalidation cannot restore the deleted note.
- Browser query composition suspends publication while peer body edits continue.
  Resuming composition publishes current membership and clears pending dirty work.
- Switching from an empty query to Exact or Fuzzy cancels old dirty-row work.
  Later body changes disable stale membership before the new search publishes.
- Date Modified reordering preserves row identity and complete membership.
- Detachment cancels delayed dirty rows, rejects later preview notifications,
  and does not publish into a replacement library session.

Relevant production paths are `NVBrowserSession.m:495–565` and the existing
composition, search, and row-identity methods that those paths call.

## Scope and limitations

Read `AGENTS.md`, `architecture.md`, the full PR diff for the source analysis,
editing-session, browser, and application coordination changes. Inspected source
generation rejection, ticket cancellation, last-layout detachment, and session
closure. No additional actionable issue was confirmed in those paths.

The headless composition check exercises browser query suspension, not native
IME behavior. It does not emulate painting, keyboard delivery, or operating-system
menus. GUI evidence comes from the root's separate actual-app run. No performance
finding is duplicated here. No production files, commits, or GitHub comments
were changed by this reviewer. Build artifacts remain under
`build/TypingReview/round1/kingsbury/`.
