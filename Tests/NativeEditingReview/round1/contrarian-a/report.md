# Round 1 contrarian review

## P2 — Bundled help advertises editing commands removed by this change

All six localized `Excruciatingly Useful Shortcuts.nvhelp` resources still
tell users that Command-[ and Command-] outdent/indent lines, Option-Tab
indents, Command-T removes styles, Command-B/I/Y apply formatting, and
Command-Left/Right jump between the title and body. The project includes this
localized resource in the application target. This branch removes the
corresponding `LinkingEditor` implementations and menu entries, including the
`keyDown:` title-jump override.

The executable audit converts every shipped RTF help resource to text and
finds all nine stale shortcuts in all six localizations. It also verifies that
the seven corresponding editor implementations are absent. Update the bundled
help in this PR so its source-editing instructions describe the native text
view behavior that users will actually get.

## P3 — The status menu's Format submenu begins with two separators

Deleting the legacy formatting commands left two adjacent separators before
the sole `Fix Text Encoding` item in the `statBarMenu` Format submenu. The same
residue is present in all six `MainMenu.xib` localizations. Remove both leading
separators; they no longer separate menu groups and produce an empty block at
the top of a user-visible menu.

## Evidence

Run:

```sh
python3 Tests/NativeEditingReview/round1/contrarian-a/run.py
```

The run also compared a freshly allocated `NSTextView`'s text-system defaults
with the XIB state. The explicit spelling-correction state matches AppKit on
this macOS version, and the continuous-spelling setting is off by default, so
I did not file a spelling-default finding. I did not automate opening the
status menu or clicking every documented shortcut; the findings are based on
the built resource graph, decoded help contents, selector inventory, and XIB
menu structure.
