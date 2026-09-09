Round two found one new P2 failure in the browser state machine.
The review used a concurrency and consistency lens, without an identity claim about Kyle Kingsbury.
The runs used the repaired working tree above `a611cee399db63eb9edb0958358469c0eda30945`.
The JSON records identify the exact source with file and method SHA-256 hashes.
Both state runs recorded stable production inputs throughout compilation and execution.

**[P2] Let a newer Reveal supersede pending window restoration**

Primary location: `Sources/Browser/AppController_Search.m:85–92`.
Reveal queues its intent at `AppController.m:1661–1664` or `1734–1736`.
Neither path replaces an older `pendingSearchRestoration`.

A browser restores a saved Fuzzy query and note while its result is pending.
Before completion, a later programmatic Reveal requests a different note or note group.
Both intents remain pending.
The completion selects the older restored note because its `if` branch precedes the Reveal branch.
The newer Reveal remains pending after the current result completes.
It requires another completion or an unrelated future refresh before it can select its target.

The singular witness restored `Road map` under the query `road`, then requested Reveal for `Other`.
Both notes belonged to the current native result.
The first completion selected the saved fuzzy occurrence of `Road map` and left Reveal pending.
An identical repeated completion selected `Other` without a new user command or corpus change.

The plural witness restored `Road map`, then requested Reveal for `Other` and `Rivet`.
The browser lost key status before completion.
The first completion selected only `Road map` and left the newer plural Reveal pending.
An identical repeated completion selected both requested notes.

This ordering also applies to plural Reveal after an import during pending window restoration.
`NotationController.m:1123` requests plural Reveal after it adds multiple notes.
`NVApplicationController.m:450` sends that request to the originating browser.
The newer programmatic request must replace or take precedence over the saved selection.

**Commands and results**

```sh
python3 Tests/FuzzySearch/Review/round-2/kingsbury/run.py
python3 Tests/FuzzySearch/Review/round-2/kingsbury/run.py --sanitize
python3 Tests/FuzzySearch/Review/round-2/kingsbury/run-appkit.py
```

The native and AddressSanitizer/UndefinedBehaviorSanitizer runs passed 52 assertions each.
The assertions include failure witnesses. A successful default run means the reported ordering failure remains reproducible.
The native AppKit probe also exited with zero.
It used real windows, a real search field, and the repaired production focus and cancellation methods.
It required execution outside the sandbox for application activation.
All binaries used arm64. No Intel process ran.

The AppKit probe recorded these states:

```text
APPKIT_INITIAL active=1 key=1 field_focus=1 pending_return=1 autocomplete=1 reveal=1 restoration=1 resign_count=0 active_loss_count=0
APPKIT_RESIGNED active=1 key=0 field_focus=0 pending_return=0 autocomplete=0 reveal=1 restoration=1 resign_count=1 active_loss_count=0
APPKIT_REENTERED active=1 key=1 field_focus=1 pending_return=0 autocomplete=0 reveal=1 restoration=1 resign_count=1 active_loss_count=0
APPKIT_DEACTIVATED active=0 key=0 field_focus=0 pending_return=0 autocomplete=0 reveal=1 restoration=1 resign_count=2 active_loss_count=1
```

`native-results.json`, `sanitize-results.json`, and `appkit-results.json` contain the complete output and source identities.
The fixture supports `--expect-fixed` for repair checks and writes separate result files in that mode.
The runs used macOS 26.5.2 (25F84) and Xcode 26.6 (17F113).

**Passing histories and limits**

The repaired focus behavior passed these additional histories:

- One, two, or three key-focus round trips canceled deferred Return and autocomplete.
- Repeated completions after re-entry did not revive canceled Return.
- A new explicit Return remained usable after the cancellation.
- Real AppKit window switching and app deactivation canceled transient intents and retained programmatic intents.
- A new query replaced pending restoration or Reveal, including after focus loss and re-entry.
- A newer saved state replaced an older saved state and preserved its caret after completion.
- Plural Reveal retained all unique target notes after background completion.
- Repeated error completions did not create a note.
- A late success from an obsolete failed request did not satisfy a newer query.

The state fixture runs the real browser session, service, corpus, query parser, and native matcher.
It extracts unchanged current methods from the three production browser files.
The fixture supplies in-memory model objects and deterministic controls. It records creation at the controller call boundary.
Its error histories intercept only the callback delivery boundary after the real service computes a request.
The real AppKit probe separately covers window switching, re-entry, and activation loss.
The review does not cover notes persistence, full application startup routing, or input-method software.

This review added only files in its round-two directory.
It made no production edits, original-test edits, round-one edits, or commits.
