# Round 2 — Linus Torvalds review

I reviewed the fixed branch as a deletion and consistency patch. The round-one
findings are resolved: the orphan helper APIs and French nib are gone, all
removed editing selectors remain absent, and all 18 localized MainMenu,
BrowserWindow, and Preferences XIBs compile with `ibtool`.

## Findings

### P2 — Delete the hidden tab-width override

The visible Tab Key and soft-tab preferences are gone, but `GlobalPrefs` still
registers and reads `NumberOfSpacesInTab`, constructs `noteBodyParagraphStyle`,
and calls `setDefaultTabInterval:` with the measured width of that many spaces.
This is active legacy editor behavior, not inert migration data: the paragraph
style is installed in every monospace note body's attributes.

The Objective-C probe creates a fresh `NSTextView`. Its typing attributes have
no explicit paragraph style and AppKit's default style reports a zero explicit
tab interval; the remaining nvALT algorithm installs a positive 28.898-point
four-space interval on this machine. Existing user defaults can silently vary
that value even though the preference is no longer exposed. Remove
`NumberOfSpacesInTabKey`, `numberOfSpacesInTab`, `_bodyFontIsMonospace`, the
cached `noteBodyParagraphStyle`, and the paragraph-style injection from
`noteBodyAttributes`.

### P2 — Fix the supported NSTextFinder ownership leak

`prepareTextFinder` executes on every supported system and assigns
`textFinder=[[[NSTextFinder alloc]init]retain]`. `alloc` already returns an owned
object, while `dealloc` releases it only once. Every destroyed editor therefore
leaks its finder. Use `[[NSTextFinder alloc] init]` with the existing release.

### P3 — Remove the now-unreachable password generator and strings

Deleting `LinkingEditor`'s custom context menu removed the only production
caller of `NVPasswordGenerator`. Its header and implementation remain in the
Preferences group and the implementation remains in the application Sources
phase, so the binary still ships a class nothing can reach. Delete both files
and their three project references.

The same deletion left localization-only entries for `New Password...`,
`Insert New Password`, `Insert Link`, `Use Automatic Text Replacement`, and
the custom `Strikethrough` command in all six `Localizable.strings` files.
Delete those dead entries as well.

### P3 — Delete unsupported finder branches and dead editor state

The documented and CI deployment target is macOS 10.13, but `LinkingEditor`
still contains Leopard/Lion runtime gates, `prepareTextFinderPreLion`, and a
private `NSTextView` compatibility category for systems older than 10.6. Those
branches cannot execute in a supported app. The related
`selectedRangeDuringFind`, `stringDuringFind`, and `noteDuringFind` ivars have
no live use; two are merely released despite never being assigned. The
`windowBecameOrResignedMain:` observer method is also disconnected. Remove the
unsupported branch, compile-time gates, dead ivars, and dead method, leaving the
modern `NSTextFinder` path directly expressed.

## Evidence executed

```text
python3 Tests/NativeEditingReview/round2/torvalds/run.py
```

The script checks the deleted selectors and category, parses and compiles all
18 localized XIBs, runs the native AppKit tab-default probe, inventories the
hidden tab override and dead password class/string resources, checks the
supported deployment target against the remaining finder branches, checks
finder ownership, and compiles the source-editing integration probe.

## Validation limits

This is a structural deletion audit with native AppKit and compile-only probes.
It does not launch the complete GUI or perform a full application build.
