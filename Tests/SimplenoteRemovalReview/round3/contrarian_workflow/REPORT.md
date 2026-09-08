# Round 3: workflow compatibility skeptic

No actionable defect introduced by this PR was found in the tested histories.
The source and command paths still work after every browser window closes.
This review used an independent contrarian perspective, not an impersonation or endorsement.

The review covered the application coordinator, browser closure, retained application services,
local UUID URL handling, and normal termination. It read `architecture.md` and the relevant
production diff from `9693356` to `f38a8cb`.

## Executable evidence

[checks.inc](checks.inc) adds original native histories to the disposable copied-app runner.
[prefix.h](prefix.h) declares the routing methods and supplies one sensitivity control.
All object access uses selectors or KVC. The probe does not assume private ivar offsets
match between old and new binaries.

Both binaries passed **48 assertions**: 32 before termination and 16 in a fresh process.
These totals include four runner assertions for opening the disposable library.

| History | Observed result in both binaries |
| --- | --- |
| Two browsers, two notes, pending native source compositions | Both models initially retain checkpoint text. Closing each browser commits its pending composition. |
| All browsers closed, quit-on-close disabled | The coordinator retains the same library and initial application-services bridge. |
| Preferences command with zero browsers | The actual coordinator forwards the action to the retained initial controller. The native window opens and its remaining preference action changes the setting. No browser is created. |
| Local UUID URL with zero browsers | The actual application delegate creates a visible browser attached to the same library. It selects the exact existing note and shows its committed source. |
| Pending source in the URL-created browser | Closing the window commits this second composition. |
| Application Reopen, then Open Untitled | Each request creates one browser on the retained library. Existing notes remain searchable and selectable. No extra note is created. |
| Normal quit with zero browsers, then fresh launch | Both exact UUIDs, titles, source bodies, tags, and local syntax identifiers survive. The changed preference also survives. |

The test writes an expected identity and text manifest outside the notes library after
checking explicit source strings. The second process compares every reopened note against it.

[current.log](current.log) and [baseline.log](baseline.log) contain the final successful runs.
[negative.log](negative.log) records the expected exit status 1 when the control creates
a browser but omits forwarding the URL to its note-reveal handler. Window creation and
visibility checks pass; the exact-note selection assertion rejects the mutation.

An initial probe used nonexistent preference syntax selectors. It was corrected to the
existing `NoteObject` syntax accessors before the final runs. An initial control that
only omitted new-window creation allowed the old initial window to reactivate. It was
replaced with the URL-reveal control to test a user-visible navigation failure.
Neither probe correction is a production finding.

## Reproduction

Run from the repository root in an active macOS desktop session:

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/SimplenoteRemovalReview/round3/contrarian_workflow/checks.inc \
  --prefix Tests/SimplenoteRemovalReview/round3/contrarian_workflow/prefix.h \
  --app build/SimplenoteRemovalReview/round1.app --launches 2
```

For the baseline, replace the app path with `build/SyntaxFlickerReview/fix.app`.
For the expected failure, prefix the current-app command with `NV_R3_OMIT_URL_REVEAL=1`.
The runner serializes GUI access, uses temporary notes and defaults, and deletes its app copy.

The current executable SHA-256 is
`d61aea6619f6c4322efac164d7409ac131aa0ce2a8760d874850c34443331ede`.
The baseline executable SHA-256 is
`ee8e9ca27c99d55ff867afabd49e75c12f5548f49ac93dc733f514f477cac365`.
The current app contains production commit `f38a8cb`; its production code is unchanged
at review head `f9cc501`. The baseline has the production content of base `9693356`.

## Limits

These are native controller and application-delegate calls, not system-delivered Apple events
or mouse clicks on the Dock. The fixture reproduces Preferences controller construction
because the runner replaces normal application startup. It does not test launch registration,
hotkeys, background services, external applications, or any removed remote-link guarantee.
The persistence check covers normal local database termination, not a crash or disk failure.
No real notes, keychain items, account settings, or network services were used.
