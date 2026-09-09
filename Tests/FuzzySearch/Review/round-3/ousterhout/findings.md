# Round 3: callback ownership and resumable work

This review uses a John Ousterhout-inspired ownership and interface perspective.
John Ousterhout did not perform or endorse this review.

No actionable introduced defect was found within this scope.

The runs used checkout `a9636d6b21b393989df27d68ec84cd3df71f0979`.
The reviewed service and browser sources match the repair at `11f571f`.
The runner copies its compilation sources before each build and records their SHA-256 hashes.
Neither run observed changes to those inputs during compilation or execution.

## New positive evidence

Commands:

```sh
python3 Tests/FuzzySearch/Review/round-3/ousterhout/run.py
python3 Tests/FuzzySearch/Review/round-3/ousterhout/run.py --sanitize
```

Both runs passed **144 checks**.
The sanitizer run used AddressSanitizer and UndefinedBehaviorSanitizer. Neither run emitted compiler diagnostics or runtime diagnostics.
These are new positive checks, not reruns of the round-two failure witness.

The fixture links the complete production browser session, search service, query parser, corpus, and native matcher.
It reuses the existing browser fixture's in-memory model and library collaborators.
It does not replace production cancellation, callback delivery, registry management, or mapping methods.

The new scheduling subclass pauses immediately before the second `runPositionBatch:` invocation calls its production superclass.
The first production mapping batch has already queued that continuation.
The semaphore gate controls timing only. The immutable work, request keys, cancellation flags, and worker queue remain under production control.

| Sequence | Observed result |
| --- | --- |
| Successful search, cached search, positions, or literal callback cancels its own channel | Its captured object remains alive until the callback returns. |
| The successful callback submits a successor, then its capture destructor submits another successor | The newest request survives. The intermediate callback is canceled without delivery. |
| The canceled successor's capture destructor submits work for another owner | The independent callback completes once. All four captures dispose on main. |
| Repeat the successful sequence through a completed cached search | Delivery remains deferred, and the cached request identity is reused. |
| Close one production browser while its second mapping continuation is paused | The browser disposes on main before the worker resumes. Its peer retains the current result identity. |
| Invalidate the old service and close both old browsers while mapping is paused | Both browsers dispose on main. A new library service completes its own search and source positions before the old worker resumes. |
| Resume canceled mapping after owner closure or library replacement | The old completion never publishes. The surviving peer or replacement browser receives its own source positions once. |
| Let queued mapping complete while its callback holds the caller's final ownership reference | Four production mapping batches finish. The callback receives the final source coordinate, then its owner disposes on main. |

The continuation cases use a 20,001-code-unit source with decomposed accents and a terminal match.
The successful case retains its captured owner across the paused continuation.
It releases that owner only after delivery on main.

## Interface assessment

Cancellation first detaches registry entries, then releases their callback captures at `NVSearchService.m:248` and `NVSearchService.m:257`.
That order permits capture destruction to submit independent or replacement requests without an outer cancellation removing them.

Successful delivery removes the callback from its work object before invocation at `NVSearchService.m:316` and `NVSearchService.m:419`.
The local callback reference preserves its captures through reentrant cancellation and releases them on main after the invocation.
The cached-result branch follows the same ownership rule at `NVSearchService.m:293`.

The position continuation at `NVSearchService.m:410` retains its work object and service.
The work stores immutable query and snapshot values, native output, mapping state, and nonretaining owner keys.
It does not retain a browser through an additional owner variable.
The new continuation therefore preserves the repaired lifetime boundary in these tests.

## Source identity

| Source | SHA-256 |
| --- | --- |
| `Sources/Search/NVSearchService.m` | `ab2cb80e9365e47ae6c82dd086022c12089aeb8da385e95e6084909f8d1a52b8` |
| `Sources/Search/NVSearchService.h` | `9f49e0ac86baa0ebe4e29c6fba362a045ffb99807d56ac3e74b34eca24c0ee43` |
| `Sources/Browser/NVBrowserSession.m` | `2ec178fde253541204b26e36c3bfce018aacb17fe0469ceecd17bfa9ce91e170` |
| `Sources/Search/NVSearchCorpus.m` | `e06314a52e03eefb1e486caa62b08993cbe27c2048659a44ae43443025134df7` |
| `Sources/Search/NVSearchQuery.m` | `5187594b6b77b48554a3e5c6b5002735b0b106a93c233bed65ec29b91460d7ce` |
| `Sources/Search/NVFZF.c` | `dd774f2e7e90ab4ffe8b9cb27f3c17f399756bf08a0455dfe846f5ea99d362b4` |

[Native results](arm64-native-results.json) and [sanitizer results](arm64-sanitize-results.json) record the commands, output, and additional source hashes.
Generated sources, executables, and compiler logs remain under `build/FuzzySearchReview/round-3/ousterhout/`.

## Limits

The runs used arm64 on macOS 26.5.2 with Xcode 26.6.
They do not establish Intel runtime behavior or macOS 10.13 compatibility.

The fixture performs the production session teardown calls and creates an independent replacement service.
It does not run the full application controller, browser windows, or a disk-backed library replacement.
The in-memory notes replace production model persistence and notifications.
No personal notes were accessed.

The deterministic gate covers a queued continuation after one mapping batch.
It does not explore every scheduling interleaving or measure worker latency.
The positive cases use successful native work and ordinary cancellation. They do not inject allocation failures or exceptions.
No production changes were necessary from this review.
