# Search callback lifetime

Run the positive ownership checks without opening the application:

```sh
python3 Tests/FuzzySearch/Lifecycle/run.py
python3 Tests/FuzzySearch/Lifecycle/run.py --sanitize
```

Use `--arch x86_64 --build-only` to compile without launching an Intel process. The default architecture is the host architecture.

The fixture links the production browser session, search service, query parser, corpus, and native matcher. It supplies an in-memory library and pauses the service worker. It does not exercise an application window or a disk-backed library.

The checks cover:

- Browser disposal on main before queued search, position, or literal work resumes.
- Cancellation by owner, position owner, literal owner, invalidation, synchronization, snapshot update, and note removal.
- Replacement of search, position, and literal callbacks, including identical search queries.
- Callback destruction that reenters cancellation or submits a new request.
- Successful callback delivery and capture disposal on main.
- No callback delivery after cancellation.

The runner exits unsuccessfully if any check fails. It writes source hashes and results under `build/FuzzySearchLifecycle/`. CI must use this positive runner, not the original failure witness.

## Round 2 repair

The service now clears completion blocks during cancellation on main. It detaches old registry entries before releasing those blocks. A callback destructor can therefore reenter the service without removing a newer request.

Replacements register their new work before disposing prior callbacks. Successful delivery moves the callback out of its worker object before invocation. Position workers validate a pointer key and request identity without capturing the browser owner.

On the local arm64 host, the repaired fixture passed 236 checks in both native and ASan/UBSan runs. The service suite passed 135 checks in both configurations. The highlight suite passed 106 checks. The Intel lifecycle executable compiled successfully; it was not launched because the host cannot run the Intel fixtures reliably.

The `arm64-*-fixed-results.json` files preserve these repaired runs and their source hashes. The original round 2 failure records remain unchanged. This compatibility command invokes the positive runner:

```sh
python3 Tests/FuzzySearch/Review/round-2/ousterhout/run-lifetime.py --expect-fixed
```
