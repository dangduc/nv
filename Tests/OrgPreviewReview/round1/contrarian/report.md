# Org preview review, round 1: contrarian perspective

The reviewed commit is `4467e7a7251ff3846c6d255db3bd64f465fda6b2`.
This review challenges the value of an Org notebook preview when ordinary notebook links and structures lose their meaning.

## P2: Resolve ordinary heading links within the current document

Location: `ThirdParty/OrgPreview/src/main.rs:59–61`.

The link handler copies Org link targets into HTML `href` attributes after it removes a possible `file:` prefix.
That works for web links and explicit `#custom-id` links.
It does not translate Org heading references into document anchors.

The fixture contains a heading with a custom ID:

```org
* TODO Release plan
:PROPERTIES:
:CUSTOM_ID: release-plan
:END:
Plan body.

[[#release-plan][By custom ID]]
[[*Release plan][By heading]]
[[Release plan][By exact heading]]
```

The helper emits `id="release-plan"` for the heading.
It emits these link targets:

| Description | Actual target | Expected target in this fixture |
|---|---|---|
| By custom ID | `#release-plan` | `#release-plan` |
| By heading | `*Release plan` | `#release-plan` |
| By exact heading | `Release plan` | `#release-plan` |

The production renderer retains both incorrect targets after sanitization.
They are relative paths without fragments, so they cannot point to the existing heading anchor.
The current navigation policy also accepts local clicks only for fragments within the current document, at `Sources/Preview/PreviewController.m:363`.
This is a code-supported navigation consequence. The probe does not click a live WebKit view.

Org defines starred heading references and exact-heading fallback as internal links.
They do not require custom Emacs export settings. [Org manual: Internal Links](https://orgmode.org/manual/Internal-Links.html).

The README advertises Org links, and the converter already supports custom heading IDs.
An ordinary notebook table of contents can therefore contain some working links and some links that cannot navigate.
Resolve supported heading references against the document and emit matching fragment URLs.
Keep a fixture that covers TODO headings, explicit custom IDs, and exact heading names through the helper and production renderer.

## Other scope observations

Three additional fixtures expose limits without an additional severity finding:

- Explicit list counters such as `[@20]` stay literal inside an ordinary `<ol>` item. The output does not apply their requested numbering.
- Description-list separators remain literal `Term :: definition` text in `<ul>` items.
- Emphasis inside a link description remains literal marker text.

The first two are standard Org plain-list forms. [Org manual: Plain Lists](https://orgmode.org/manual/Plain-Lists.html).
The current README uses the broad word “lists” without these distinctions.
Explicit documentation of these limits can set expectations for the first preview release.

## Evidence and positive checks

`run.py` generates ten disposable fixtures and uses the actual bundled helper.
It also compiles the unchanged production renderer and snapshot classes.
The executable in the built app matches the checked-in helper.
Its SHA-256 is `34d4469bb611c062a0730040ed1224228262e13d249b5437316947f433fe4359`.

Twenty of 24 expected-output checks pass.
Four fail: two internal-link forms, each through the helper and renderer.
The runner exits with status 1 to retain these failures as executable evidence.
The separate native harness passes all 40 completion, source-preservation, and output checks.
Every input file retains its original hash.

The passing checks cover task labels, all three checkbox states, Unicode, nested lists, web targets, literal spans, and comma escapes in example blocks.
They also cover an unfinished source block and an unfinished link.
Both partial constructs retain their visible source contents.
The literal and checkbox expectations follow the Org manuals. [Emphasis and Monospace](https://orgmode.org/manual/Emphasis-and-Monospace.html), [Checkboxes](https://orgmode.org/manual/Checkboxes.html).

Run the evidence:

```sh
python3 Tests/OrgPreviewReview/round1/contrarian/run.py
```

`results.json` records all expected-output results and the additional scope observations.
`renderer-output.txt` records the native checks.
`metadata.json` records the source, converter, and fixture hashes.
The host runs macOS 26.5.2 through Rosetta with Xcode 26.6.
These checks do not cover live WebKit navigation, source-editor Undo, or complete Emacs Org export semantics.
