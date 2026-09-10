# Round 3 — contrarian B review

## Result

No additional actionable finding in the boundaries reviewed. The legacy Find
connections in each main nib initially look suspicious because they name that
nib's embedded `LinkingEditor`, but application startup deliberately retargets
view actions to `NVApplicationController`. Its forwarding path resolves the
active browser, whose preview category chooses the source editor or viewer.
The two-window runtime probe confirmed that this indirection routes Find to the
active second window and leaves the first editor untouched.

## Executable evidence

Run:

```sh
python3 -B Tests/NativeEditingReview/round3/contrarian-b/run.py
```

The structural probe passed 20 checks across all six localizations. It verified
that each main nib has one unambiguous Find connection source, and that the
application and browser forwarding stages remain present.

The disposable app probe passed 18 runtime checks, including its two startup
checks. With two notes open in two windows, it verified the active source view,
application-level menu retargeting, active-browser forwarding, native
first-responder routing for `selectAll:`, and Find-bar isolation. It then drove
an IME-style marked-text insertion and commit through both the source editor and
a fresh plain `NSTextView`; characters, selections, and marked ranges matched.
The note model did not receive the provisional marked text and did receive the
committed text. Finally, the source and reference views exposed equal
accessibility roles, values, and selected-text ranges.

## Validation limits

The input-method check calls the `NSTextInputClient` methods directly; it does
not operate a real candidate window or cover every keyboard layout. The
accessibility check queries AppKit in process and does not drive VoiceOver. The
Find check opens the native bar through the real main-menu target, but does not
inspect replacement controls or preview WebView pixels.

The run uses a disposable copy of the current Derived Data application. A fresh
repository build is independently blocked at this revision by the orphaned
`IBeamInverted.png` project reference reported by other round-three reviewers.
No production code changed during this review.
