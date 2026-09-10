# Round 2 contrarian A review

Reviewed `7ed3d68` as a challenge to the claim that source editing now follows
native `NSTextView` behavior. The audit covered all six localized Preferences,
main-menu, and browser-window XIBs; compiled those 18 XIBs; checked the public
formatted-import and storage-format boundaries; and ran a disposable app probe.

## P3: the old tab-width preference still overrides native paragraph layout

`GlobalPrefs` still registers `NumberOfSpacesInTab`, exposes
`numberOfSpacesInTab`, removes every tab stop from the default paragraph style,
and installs an interval sized from that hidden preference. These pieces served
the deleted soft-tab and custom indentation implementation. There is no longer a
UI for the value, but a saved/defaults-domain value still reaches the live
preferences object.

The app probe launched with `-NumberOfSpacesInTab 11`. `GlobalPrefs` returned an
11-space interval of 79.471 points and no tab stops. The same tab placed the next
glyph at x=84.471 with that style and x=33.000 in a fresh plain `NSTextView`.
AppKit's paragraph had 12 native tab stops and no replacement default interval.

Remove `NumberOfSpacesInTabKey`, `numberOfSpacesInTab`, and the custom
`noteBodyParagraphStyle` construction. The body font can remain an editor
appearance preference without replacing AppKit's paragraph tab layout.

## Boundaries that passed

- Each localized Editing pane has only the clickable-URL and external-editor
  actions. Removed spelling, Tab, soft-tab, auto-pair, note-link suggestion,
  styled-paste, and RTL actions are absent.
- Native spelling and substitution menu actions target the first responder in
  every main-menu XIB. Removed formatting and indentation actions are absent.
- Both source-editor XIB copies per locale are plain text, reject graphics, and
  opt into the native smart insert/delete default found in Round 1.
- Formatted document imports remain rejected, and the storage Preferences
  controller prunes every format except database and plain text.

Run `python3 Tests/NativeEditingReview/round2/contrarian-a/run.py`. It records the
full result in `output.txt`. The runtime portion passed 10 checks after the
localized/static audit passed 9 groups of checks.

The probe did not drive VoiceOver, keyboard-navigate the Preferences window, or
perform every export operation. It measured the app's live preference object and
the resulting AppKit layout in a disposable application process; it did not
claim that every note currently receives the style on every font path.
