# Round 2 — contrarian B review

## Result

The decoded source editor now matches a plain `NSTextView` across the checked
text-system settings, Unicode deletion fixtures, multiple-selection replacement,
bindings, and ordinary menu validation. One legacy input-event override remains.

## Finding

### P2 — `LinkingEditor` still replaces native modifier-key handling

`Sources/Editor/LinkingEditor.m:681-683` overrides `flagsChanged:` and forwards
the event only to `AppController`; it never calls `NSTextView`. The controller's
handler at `Sources/Browser/AppController.m:2370-2386` starts the old Option-hold
word-count timer or posts `ModTimersShouldReset` for every other modifier event.
This is source-editor-specific input policy even though the redesign promises
native text editing.

The runtime probe temporarily instruments `-[NSTextView flagsChanged:]` without
changing production code. A synthesized Shift modifier event sent to a plain
text view crosses the native implementation once. The same event sent to the
active source editor crosses it zero times and emits the legacy timer-reset
notification instead. This proves the subclass consumes the event rather than
augmenting AppKit behavior.

Remove `-[LinkingEditor flagsChanged:]` so the source view inherits AppKit's
implementation. If the Option-hold word count shortcut must remain for other
parts of the app, keep that concern outside the source editor's responder
implementation.

## Evidence executed

```text
python3 Tests/NativeEditingReview/round2/contrarian-b/run.py
```

The executable probe passed 35 application checks. It compared Smart Copy/Paste,
spelling and grammar, corrections, substitutions, link and data detection,
enabled text-checking types, writing direction, and value bindings with a fresh
plain `NSTextView`. Backspace results and selections matched for CRLF, combining
marks, regional-indicator flags, keycaps, a family emoji sequence, Hebrew text,
and Unicode line separators. Multiple-selection replacement and an ordinary
first-responder menu validation also matched.

## Validation limits

The modifier event is a real AppKit `NSEvent` dispatched directly to each view,
not a physical keyboard event. The probe proves that the source subclass bypasses
the framework method and invokes the word-count path; it does not claim a specific
visible failure inside AppKit. It exercises one ordinary menu-validation action,
not every menu item. No production code changed during this review.
