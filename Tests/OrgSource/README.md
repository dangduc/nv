# Org source analysis

Run `python3 Tests/OrgSource/run.py` from the repository root.
The runner compiles the production parser, highlighter, and vendored grammar wrappers for Intel with a macOS 10.13 deployment target.
It uses Cocoa text storage and layout managers without launching the app.

The checks cover Org captures, UTF-16 bounds, and incremental results after seven edits.
They include task-word boundaries, ordinary emphasis, nested literals, comments, source blocks, and missing closing block syntax.
Other checks cover query predicate rejection, cancellation, large-note fallback, and recovery.
Two attached layouts check provisional colors during typing, replacement captures, search backgrounds, and switching to Plain Text.
The runner also checks the Org dependency hashes and query hash.

The supplemental pass recognizes default TODO and DONE words at the start of a heading.
It recognizes `*bold*`, `/italic/`, `_underline_`, `+strike+`, `=verbatim=`, and `~code~` in prose with ordinary Org delimiter boundaries.
An emphasis span can contain one newline. Literal spans suppress emphasis within their contents.
Parser-selected blocks, comments, directives, drawers, links, and inline source blocks exclude supplemental emphasis.
The comment pass also handles a comment directly after a directive, where the pinned grammar otherwise emits paragraph expressions.

The tests use fixed fixtures. They do not establish full Org conformance or macOS 10.13 runtime behavior.
The existing parser and display budgets still apply. A successful parse can exceed the display limit and use plain source colors.

Run `python3 Tests/OrgSource/Links/run.py` for the source link checks.
This runner compiles the unchanged production decoration methods into a native probe.
It covers web targets, Unicode labels, unresolved targets, edits, and switching between Org and Plain Text.
The first pass supports single-line bracket links. File, ID, and heading targets remain inert.

After a Development build, run `python3 Tests/OrgSource/Integration/run.py` in an active desktop session.
The runner uses a copied app with a temporary library and settings domain.
It covers menus, shared editors, Undo, syntax archives, source exports, encoding preservation, and directory reconciliation.
Migration checks retain the selected output extension and preserve a later user removal of `.org` from the library filter.
The import fixtures cover UTF-8, UTF-16, UTF-32, their byte-order marks, and unmarked MacRoman source.

Set `NV_UI_ARTIFACTS` to an output directory to capture the disposable Org source window.
The [screenshot guide](../../docs/screenshots/README.md#org-source) contains the command and host details.
