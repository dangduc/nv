Round 2: contrarian review of empty states and browser closure

This review found no actionable regression at production commit `162c872` against the diff from `b27af28`.
The native probe passed 206 checks across three histories. The count includes repeated menu-presence and menu-state checks.
This round extends the earlier selected-note and toolbar histories with empty libraries, empty search results, and zero open windows.

The probe established these results:

- An empty library accepts Search commands with its toolbar, notes list, and every header row hidden.
- Native Search input reaches an empty result. Tab retains Search focus and creates no note. Return creates exactly one correctly titled note.
- Native body input resolves through the responder chain and commits the exact source characters.
- Native Delete removes the last note. Note-specific commands become disabled, while Search, New Note, New Window, and visibility commands remain enabled.
- Closing every window retains the shared library. View menu commands still update the settings through the retained application owner.
- The New Window menu and the application reopen callback each create one browser over the same library.
- Both new browsers apply the hidden-row settings. New Note focuses editable Source after an empty library or an unmatched query.
- Show Notes List restores both notes and the new note selection after both reopen paths.

The code evidence supports these results:

| Boundary | Code evidence |
| --- | --- |
| Empty-state menu access | [AppController.m:452](https://github.com/fastducduc/nv/blob/162c8721484088496f14a032027c79c3855e5ea9/Sources/Browser/AppController.m#L452) keeps New Note and visibility commands available, while note-specific actions depend on selection. |
| Empty Search creation | [AppController.m:1062](https://github.com/fastducduc/nv/blob/162c8721484088496f14a032027c79c3855e5ea9/Sources/Browser/AppController.m#L1062) routes Return through `fieldAction:`. The Tab handling starts at line 1087. |
| Hidden Title and New Note | With the Title setting hidden, [AppController_BrowserUI.m:301](https://github.com/fastducduc/nv/blob/162c8721484088496f14a032027c79c3855e5ea9/Sources/Browser/AppController_BrowserUI.m#L301) clears the query and focuses Source. |
| New browser settings | [AppController_BrowserUI.m:138](https://github.com/fastducduc/nv/blob/162c8721484088496f14a032027c79c3855e5ea9/Sources/Browser/AppController_BrowserUI.m#L138) registers the settings callbacks and applies the notes-list visibility during setup. |
| Released empty-state space | [AppController_BrowserUI.m:232](https://github.com/fastducduc/nv/blob/162c8721484088496f14a032027c79c3855e5ea9/Sources/Browser/AppController_BrowserUI.m#L232) applies the same body frame to the source and status views. |
| Closure and shared library | [AppController.m:1805](https://github.com/fastducduc/nv/blob/162c8721484088496f14a032027c79c3855e5ea9/Sources/Browser/AppController.m#L1805) finishes editing and clears selection. [NVApplicationController.m:228](https://github.com/fastducduc/nv/blob/162c8721484088496f14a032027c79c3855e5ea9/Sources/Application/NVApplicationController.m#L228) removes the browser. |
| Reopen and command routing | [NVApplicationController.m:356](https://github.com/fastducduc/nv/blob/162c8721484088496f14a032027c79c3855e5ea9/Sources/Application/NVApplicationController.m#L356) opens a browser after all windows close. Menu forwarding starts at line 364. |

The empty-list collapse also produced one recorded focus observation.
With the toolbar hidden and no selected note, the window became the first responder.
The fallback at [AppController_BrowserUI.m:170](https://github.com/fastducduc/nv/blob/162c8721484088496f14a032027c79c3855e5ea9/Sources/Browser/AppController_BrowserUI.m#L170) does not restore the hidden toolbar.
The next native Search command restored visible editing. Every subsequent creation and reopen path passed.
This observation did not establish a loss of product access or an actionable defect.

With the Title control hidden, the mutation forced unconditional Title focus after New Note.
It failed at the exact Source-focus assertion in the reopened empty library.
The mutation ran only inside the disposable process. Production code and the app bundle remained unchanged.

Run the normal probe:

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/ViewControlsReview/round2/contrarian/checks.inc \
  --app build/ViewControlsReview/round1/nvALT.app \
  > Tests/ViewControlsReview/round2/contrarian/output.txt 2>&1
```

Run the mutation control:

```sh
NV_C2_LEGACY_NEW_NOTE_FOCUS=1 python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/ViewControlsReview/round2/contrarian/checks.inc \
  --app build/ViewControlsReview/round1/nvALT.app \
  > Tests/ViewControlsReview/round2/contrarian/mutation-output.txt 2>&1
```

The normal command returned 0. The mutation command returned 1 with the expected focus failure.
An initial fixture used an incorrect preference selector. `initial-fixture-failure.txt` records that harness error, which the corrected probe no longer contains.

The environment used macOS 26.5.2 (25F84), Xcode 26.6 (17F113), and the frozen Intel Development app under Rosetta.
Each run used desktop escalation, a copied app, disposable notes, unique settings, and `build/pr-review/gui.lock`.
The review included `AGENTS.md`, `architecture.md`, the production diff, and the relevant control, menu, and lifecycle paths.

The probe used 780-point content widths and Source mode. It did not cover additional locales, physical keyboard events, or accessibility navigation.
The Dock history called the native delegate callback directly. It did not click the Dock icon.
The probe did not restart the app process or run the base app. It established no failure that required a runtime baseline comparison.
No production files, commits, pushes, or PR comments changed during this review.
