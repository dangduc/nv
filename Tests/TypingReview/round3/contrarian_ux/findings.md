# Round 3 — contrarian UX review

No introduced regression is confirmed by this probe. The retained-menu activation question remains unverified.

Production source is at `5eda58b`, with review HEAD `d93f935`. The exact comparison app is from base `8dde5e8`.
The candidate passed 13 native checks; the base passed 11. See `candidate-output.txt`, `baseline-output.txt`, and their result files.

## Executed evidence

The harness loads into a copied app with a unique bundle identifier and disposable notes, support paths, and preferences.
It creates two real browser windows displaying one shared note. It obtains Cocoa menus through production `LinkingEditor.menuForEvent:`.
The note begins with `https://example.com/old`. The peer editor replaces `old` with `new` after the first editor creates its menu.

The candidate confirms:

- Both native editors share the same text storage.
- The peer character edit marks source-link analysis obsolete.
- A menu requested while analysis is pending removes the obsolete `NSLinkAttributeName` value.
- Fresh analysis completes after that removal and publishes `https://example.com/new`.
- A subsequent native menu contains Open Link.

A retained native menu still has an enabled Open Link item after the peer edit and `[menu update]`.
The exact base app has the same enabled-menu observation. Both use Cocoa's `_openLinkFromMenu:` action, with nil explicit target and represented object.
This is evidence about menu state only. It does not establish a stored obsolete target or an introduced regression.

The candidate's additional menu request while pending still returns an Open Link item even though its source link attribute is nil.
The initial assertion that attribute removal must also remove the menu item was unsupported; it was replaced with an observation.
The final candidate run checks attribute removal and fresh publication directly.

## Action validation limit

The probe dispatches each native menu item's actual action through `NSApp.sendAction:to:from:`.
It intercepts public NSWorkspace URL-opening entry points so a reached activation cannot open an external browser.
The action dispatch returns YES, with LinkingEditor as first responder, but no URL reaches those interceptors.
Crucially, the fresh, unchanged-link control also produces no intercepted activation, on both candidate and base.
`initial-activation-control-output.txt` preserves the failed positive-control assertion from the first GUI run.

Therefore, the empty activation logs do not prove that retained menu actions are safe.
They also do not prove that an obsolete target can open. This harness does not reproduce Cocoa's active menu-tracking state.
It directly invokes peer editing after constructing the menu; it does not establish that this edit occurs during a user's tracked menu interaction.
The bounded experiment stops at this limit. No action-time safety guarantee or stale-target bug is claimed.

The optional current-link helper returns YES on the base, where asynchronous source analysis does not exist.
Thus base log messages referring to analysis availability do not measure asynchronous completion; they allow the same menu sequence to run.
The base publishes the new source link synchronously in this sequence.

## Reproduction

On an active macOS desktop session:

```sh
python3 Tests/TypingReview/round3/contrarian_ux/run.py --output build/TypingReview/round3/contrarian_ux/candidate
python3 Tests/TypingReview/round3/contrarian_ux/run.py --app /Users/duc/dev/nv/build/SpaceCaretWorktree/build/DerivedDataTypingBaseline/Build/Products/Development/nvALT.app --output build/TypingReview/round3/contrarian_ux/baseline
```

The first sandboxed launch terminated before executing checks. The native GUI runs used the authorized desktop execution path.
No regular app, user library, production source, commits, or external messages were changed.
