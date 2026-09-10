# Round 2: viewer API and per-window ownership

This review uses a John Ousterhout-inspired perspective without impersonation.
No actionable API or ownership defect appeared in the reviewed paths.
The new native probe passed **43 assertions**, including four launch-isolation checks.
Some assertions repeat across three malformed saved-state cases and five disabled commands.

## Reviewed state

The worktree HEAD is `415cf6920bd5c74bc3911829431f3dcff7c4acb2`.
The comparison base is `f3a8abb2b7942d06ec33af64b4946cfd1b6db163`.
The run also includes the frozen, uncommitted fragment-identity fix in `PreviewController.m`.
Its SHA-256 is `e786f468b82d7ae45c59adb3aed5123bcaa6dc3b757145ead9b219e90b79436a`.
The launcher requires that exact source hash before the run.
The [evidence manifest](evidence.json) records the provider diff, production source hashes, app hash, and helper hash.

## Executable evidence

Run the probe from the preview worktree:

```sh
python3 Tests/OrgPreviewReview/round2/ousterhout/run.py
```

The [launcher](run.py) copies the production app into a temporary directory with isolated notes, preferences, and support files.
It holds the common `build/pr-review/gui.lock` during the run.
The [probe](probe.inc) calls actual browser, source session, and provider methods in two native windows.
The provider uses real WebKit documents and the bundled Org helper.
The [output](output.txt) records each assertion.

The probe covers these new sequences:

- An empty Source window disables note-dependent commands and creates no provider, including after direct viewer API calls.
- An unknown viewer input retains the previous supported identifier without an allocation.
- A selected note and a new peer window remain in Source without a provider allocation.
- Unknown, numeric, and missing saved identifiers retain a supported viewer through actual browser restoration.
- Invalid per-format state does not change source metadata, source characters, or the peer window.
- Two independent providers render the same Plain Text note as Org, with one shared source storage.
- Both real documents change to different heading fragments and scroll positions.
- Concurrent public capture requests return their own offsets, queries, snapshots, and viewer identifiers exactly once.
- Restoring one window with a missing note clears that window and closes its old provider.
- The peer provider and source session remain intact. A capture after closure completes synchronously once.
- All sequences preserve source syntax, source characters, source generation, modification dates, and Undo history.

## Fragment fix assessment

The fix removes only the literal fragment suffix before the existing document-base comparison.
It leaves snapshot ownership, asset scope, request revisions, and completion delivery unchanged.
The remaining comparison still includes the scheme, host, path, and query under the existing case-insensitive rule.
An encoded hash remains part of that comparison.

The new sequence exercises that boundary through public capture calls in two windows.
The fixture disables both periodic state timers before it changes either fragment.
The cached offsets start at zero. WebKit then reports different nonzero offsets for the two windows.
Both capture callbacks return those actual offsets and their separate Find queries.
The fallback deadlines produce no additional callbacks.
This evidence supports the fix without substituting a DOM reply or the production capture method.

## Limits

The run used macOS 26.5.2 and Xcode 26.6, with the Intel app through Rosetta.
It does not establish operation on macOS 10.13.
Window restoration occurs within one process, not through an app relaunch.
The probe directly changes heading fragments through WebKit JavaScript. It does not simulate a physical mouse click.
Periodic state timers are intentionally inactive during the fragment checks.
The probe does not repeat the maintained URL-variant matrix or assess broad Org fidelity, performance, composition, or Undo after source edits.
No production files changed for this review.

