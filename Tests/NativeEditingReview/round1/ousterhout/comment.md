### Round 1 review — John Ousterhout perspective

I reviewed the change as an abstraction-boundary simplification and ran
`python3 Tests/NativeEditingReview/round1/ousterhout/run.py` against the built
Intel app. All 13 runtime checks passed. Seven ordinary editing commands resolve
directly to `NSTextView`, while nvALT's shared-session and display integration
remain in the subclass.

**Medium — remove the remaining source-specific completion delegate.**
`AppController.m:1551-1555` still supplies library note titles through
`textView:completions:forPartialWordRange:indexOfSelectedItem:`. The probe created
a uniquely titled note and confirmed that the actual source-editor delegate
returns it. Because `LinkingEditor` inherits `complete:` from `NSTextView`, users
can still request this domain-specific completion in ordinary source text. This
leaves a controller-side exception to the new native-editing boundary.

Remove the body `textView:completions:...` method and retain the separate
`control:textView:completions:...` path used by the tag field. Then assert in the
native-editing suite that the source editor delegate does not implement the body
completion hook.

Validation limit: the probe exercised the real delegate and its returned corpus,
but it did not select an item from the visual completion panel or inspect IME and
accessibility behavior.
