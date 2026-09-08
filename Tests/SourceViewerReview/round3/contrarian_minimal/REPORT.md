# Round 3: complexity deletion advocate

Review baseline: `9720676ccd0e619dba99f6a47d257216c1e383eb`, with the Development app from the second-round build.
This review examines retained provider costs after a browser uses Preview.
The earlier resource and initial-allocation audits remain separate evidence.

No new actionable finding was demonstrated.

## Executable evidence

`run.py` passed **27 checks**. The complete output is in `output.txt`.
The runner compiles `instrumentation.h` and `probe-body.m` into a copied application.
It uses disposable notes, a separate defaults domain, and the shared GUI lock.
Production methods remain unchanged. Method wrappers count renderer submissions, timer callbacks, WebKit scroll reads, and provider lifetimes.

| Exercise | Observed result |
| --- | --- |
| Visible Preview | Two periodic DOM reads establish the measurement control. |
| Twenty edits in Source after Preview | Eight timer callbacks, zero periodic DOM reads, and zero renderer submissions. |
| Return to Preview | The provider renders the final source edit. The browser reuses its original provider. |
| Ordered-out Preview window | Four timer callbacks and zero periodic DOM reads. Reads resume after the window returns. |
| Discard plus three browser closures | Four initializations, four first close calls, and four deallocations. |
| After all providers close | Zero additional timer callbacks, DOM reads, or renderer submissions during the 0.8-second observation. |

The exact timer counts depend on scheduling. Assertions require actual timer callbacks during each visibility measurement.
The assertions require zero DOM reads and zero renderer submissions in the corresponding inactive paths.
Provider release assertions allow three seconds for asynchronous callbacks to finish.

## Negative control and fixture correction

The `NV_MINIMAL_FORCE_HIDDEN_POLL=1` control forces one harmless WebKit scroll read for each hidden timer callback.
The control records nine extra DOM reads and exits 1 at the expected hidden-source assertion.
Its complete output is in `negative-control.txt`.
This control proves that the instrumentation observes actual WebKit submissions, beyond method entry counts.

The first fixture held its own KVC inspection references in the outer autorelease pool.
That fixture reported a false provider-release timeout.
The final probe drains explicit inspection scopes before measuring application ownership, as a normal event turn does.
All four provider release checks then passed without production changes.

## Commands and limits

```sh
python3 Tests/SourceViewerReview/round3/contrarian_minimal/run.py
NV_MINIMAL_FORCE_HIDDEN_POLL=1 python3 Tests/SourceViewerReview/round3/contrarian_minimal/run.py
```

The probe ran on macOS 26.5.2 with the unsigned Intel application under Rosetta.
It measures application method calls and object lifetimes. It does not measure CPU energy, WebKit process memory, or framework caches.
The retained provider still receives inexpensive timer callbacks in Source and in an ordered-out window.
Those callbacks return before WebKit work. This review did not demonstrate a material cost that warrants another visibility lifecycle mechanism.
The concurrent capture-state and archived-encoding corrections are outside this probe's scope.
