Round 1 — contrarian review: ordinary note semantics

**[P2] Keep hashtag prose out of the comment scope.**

`NVOrgProtectedNode` in `Sources/Editor/NVSourceHighlighter.m:169–171` trusts every grammar `comment` node.
The query at `Resources/Syntax/org.scm:6` also colors the entire node as a comment.
For ordinary source `#travel *book tickets*`, production analysis returns only a comment capture and loses the expected emphasis.
Org requires whitespace after `#` for a comment. [Org comment rules](https://orgmode.org/manual/Comment-Lines.html).

The same error occurs with leading spaces, after a blank line, and after an actual comment.
With `#+TITLE: Trip` immediately before the hashtag line, the unchanged prose receives the expected emphasis instead.
This makes colors depend on an unrelated preceding directive.

Normalize grammar comment nodes with the Org prefix rule before applying comment captures and emphasis exclusions.
Combined comment nodes need a check for each line.
Actual comments and literal blocks must remain protected.

I wrote and ran native code against the production parser and link methods.
The parser recorded 18 fixtures, four instances of this error, and 31 successful capture-bounds checks.
The link probe passed 20 checks, including a newline insertion within a label.
Evidence and reproduction commands are in `Tests/OrgSourceReview/round1/contrarian/`.

These probes ran on macOS 26.5.2 with Xcode 26.6, using x86_64 through Rosetta.
They do not establish full Org conformance or macOS 10.13 runtime behavior.
