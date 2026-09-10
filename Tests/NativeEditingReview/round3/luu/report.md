# Round 3 — Dan Luu review

## Result

Two actionable findings.

### P1 — deleting the custom I-beam asset broke the normal build

`Resources/Images/IBeamInverted.png` was deleted in the round-two fix, but
`Notation.xcodeproj/project.pbxproj` still contains all four references: the
`PBXBuildFile` at line 154, `PBXFileReference` at line 406, Images group entry at
line 978, and Resources phase entry at line 1997.

The repository's prescribed Development build fails:

```text
error: Build input file cannot be found: '.../Resources/Images/IBeamInverted.png'
** BUILD FAILED **
```

The same command succeeds with
`EXCLUDED_SOURCE_FILE_NAMES=IBeamInverted.png`, which isolates the failure to the
orphan project entries. Remove those four entries rather than restoring the
unused cursor image.

### P2 — Find Next replaces the active find string with clipboard text

`LinkingEditor.m:656-682` still gives most Find commands a legacy preamble. When
the note search field is empty, it reads the general pasteboard and writes that
value into `NSPasteboardNameFind` before dispatching the native text-finder
action. Consequently, `Edit > Find > Find Next` does not necessarily continue
the current source-text search.

The executable probe selected `needle`, invoked **Use Selection for Find**, and
verified that the Find pasteboard contained `needle`. It then put
`clipboard-decoy` on the ordinary clipboard and invoked **Find Next**. nvALT
changed the Find pasteboard to `clipboard-decoy`; a fresh plain `NSTextView`
performing `NSTextFinderActionNextMatch` left `needle` intact.

Remove the search-field/general-pasteboard import from
`performFindPanelAction:` and only translate the old menu tags to
`NSTextFinderAction` values before forwarding to AppKit. That also makes
`lastImportedFindString` unnecessary. Preserve a regression check that Find
Next and Find Previous do not mutate the active Find pasteboard.

## Executable evidence

Run:

```sh
python3 -B Tests/NativeEditingReview/round3/luu/run.py
```

The disposable Intel app probe passed 92 runtime checks. It compared the real
source editor with a fresh `NSTextView` for nine consecutive Backspaces in the
reported whitespace fixture; delete-backward across surrogate pairs, combining
marks, emoji ZWJ sequences, flags, an Indic conjunct, Arabic text, and CRLF;
word and forward deletion; Tab and Return; a window-backed `keyDown:` event;
modifier events; plain, RTF, and HTML paste; completion ownership; and all six
first-responder Text-menu toggles. It also verified native method identity for
paste and drag/drop entry points and launched with every removed editing default
set to a conflicting value.

The structural portion audits all six localizations for plain editor decoding,
the standard Text and Find commands, removed preference controls, and updated
help. It also directly records the four orphan I-beam project references.

Because the ordinary project build is blocked by the P1 finding, the runtime
probe used an app built with the missing resource excluded. No production source
was changed for that workaround.

## Validation limits

The probe sends one synthetic Backspace event to active, window-backed text
views. It does not use a physical keyboard, drive an IME candidate window, open
the completion panel, or perform a real drag session. Drag/drop coverage is
limited to proving that the source editor inherits AppKit's entry points. The
Find checks exercise the shared pasteboards and dispatch methods without
asserting find-bar pixels.

No production code changed during this review.
