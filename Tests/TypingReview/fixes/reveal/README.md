# Reveal after an invalidated browser projection

The fix preserves the stale-row guard introduced by PR #24. An explicit Reveal
refreshes an invalidated Exact or empty-query projection before testing whether
it must wait. The regular library refresh respects composition and inline editing.

If an inline editor blocks that refresh, the next current synchronous publication
completes pending Reveal or restoration work. This completion runs only when an
explicit selection intent exists. The existing composition and recursive-result
guards remain in the completion handler.

Changed production methods:

- `AppController.m`, `revealNote:options:`: refresh a synchronous projection first.
- `AppController_Search.m`, `browserSessionSearchStateDidChange:`: deliver explicit
  selection intents after a blocked synchronous refresh becomes current.

## Executed checks

```sh
python3 Tests/TypingReview/fixes/reveal/run.py
```

Result: exit 0; **36 assertions passed across six scenarios**:

1. Exact Reveal selects a newly added matching note and retains the query.
2. Exact Reveal selects an excluded note after clearing the query.
3. Empty-query Fuzzy Reveal selects synchronously.
4. An inline editor blocks selection; ending editing delivers the intent once.
5. Composition blocks publication. Committing a new query still cancels old intent.
6. An active Fuzzy query waits for native search, then delivers the intent once.

The checks also verify that model invalidation blocks stale row actions and that
Reveal without an order-front option does not call the background window's
activation method. See `fixed-output.txt` and `fixed-results.json`.

The control run uses the same assertions with the controller methods extracted
from `b3c2162`, before the fix:

```sh
python3 Tests/TypingReview/fixes/reveal/run.py --before-fix
```

Result: expected exit 1 at the first immediate-selection assertion. The fixture
and stale-row guard assertions pass first. See `before-fix-output.txt`.

The runner compiles the complete browser session and native search implementation.
It extracts Reveal, state-change, completion, and cancellation methods without
changing their logic. In-memory library and view doubles provide their surroundings.
All waits have deadlines; the native process has a 30-second timeout.
Compiled artifacts stay under `build/TypingReview/fixes/reveal/`.

This probe does not launch the application or validate native window focus.
The root review separately rebuilt the app and reported all **52 editing regression
checks** passing after the fix. The original round-one evidence is unchanged.
