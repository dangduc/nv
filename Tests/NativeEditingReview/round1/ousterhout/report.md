# Round 1 — John Ousterhout review

## Result

The change makes the source editor substantially deeper: seven ordinary editing
commands now stay behind the `NSTextView` interface, while `LinkingEditor` keeps
the integration hooks for shared note history, links, highlighting, and layout.
One source-specific editing policy still leaks through the editor delegate.

## Evidence

I ran:

```sh
python3 Tests/NativeEditingReview/round1/ousterhout/run.py
```

The injected runtime probe passed 13 checks against the built Intel application.
It established that `deleteBackward:`, `insertNewline:`, `insertTab:`,
`insertBacktab:`, `insertText:replacementRange:`, `performKeyEquivalent:`, and
word selection resolve to the implementations on `NSTextView`. It also created
a uniquely titled note, selected another note in the source editor, and asked the
editor's actual delegate for completions. The delegate returned the unique note
title.

## Finding

### O1 — Medium: note-title completion remains a source-editor behavior

`AppController.m:1551-1555` still implements
`textView:completions:forPartialWordRange:indexOfSelectedItem:` for the body
editor and fills the result from the note-title corpus. The runtime probe
confirmed that the browser is the source editor's delegate and that this method
returns a library note title. `LinkingEditor` inherits `complete:` from
`NSTextView`, whose completion path consults that delegate hook.

This leaves a domain-specific editing policy outside the otherwise narrow
`LinkingEditor` boundary. A user can still request note-title completion in plain
source text, including outside a note link. That contradicts the stated goal of
using ordinary `NSTextView` editing behavior and makes the remaining abstraction
harder to describe: editing commands are native except for a policy hidden in a
controller delegate.

Remove the body-editor `textView:completions:...` method from `AppController`.
Keep `control:textView:completions:...`; that is a separate path for the tag
field and does not add source-editor behavior. Extend the native-editing probe to
assert that the source editor delegate no longer implements the body completion
hook.

## Validation limits

The probe exercised the built app and real library/controller/editor objects. It
called the completion delegate directly instead of choosing a result from the
visual completion panel. It did not inspect pixels, input-method composition, or
accessibility behavior. No production code changed during this review.
