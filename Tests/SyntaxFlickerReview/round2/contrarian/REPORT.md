# Round 2: contrarian review

No actionable defect introduced by PR #6 was found in this scope.

This review tests the real browser search interaction left outside Round 1. The reviewed production revision is `65e1608`. The PR base is `8cd2c95`.

## Evidence

The fixed application passed **133 native checks**. The baseline passed **127 common checks**. See [checks.inc](checks.inc), [prefix.h](prefix.h), [output.txt](output.txt), and [base-control.txt](base-control.txt).

Three histories covered Markdown, HTML, and JSON. Each history used two browser windows with the same source note. The first window searched for `alpha`; the second searched for `beta`.

The fixture used `searchForString:` and note selection to create actual browser queries and search highlights. It installed no temporary attributes. Each background assertion checked the drawing delegate at every source character against independently calculated query match positions.

- Both windows initially displayed exactly their own query matches.
- Native source insertion made syntax analysis obsolete before the run loop resumed.
- Unchanged tokens retained their drawn syntax colors in both windows of the fixed application.
- Native editing cleared the active editor's search backgrounds. The peer retained its previous query ranges.
- The application preference callback rebuilt search backgrounds from each window's actual query while syntax analysis remained pending.
- Native Undo and Redo preserved exact shared source. Query refresh after each operation produced exactly the expected match positions.
- Fresh syntax results preserved both windows' independent query backgrounds and token colors.
- During pending analysis, one window switched to a plain note that matched both queries. Every character used the default foreground color.
- The plain note displayed only the active window's query backgrounds. Old syntax did not enter the drawing result.
- The peer retained its provisional syntax colors during the switch. Returning attached the original shared storage and received fresh syntax.
- Final committed source matched the complete native edit history.

## Baseline control

The same fixture ran against `build/ViewControlsReview/round1/nvALT.app`, built at `162c872`. Its highlighter and editor source match PR base `8cd2c95`. This comparison produced no differences:

```sh
git diff 162c872 8cd2c95 -- \
  Sources/Editor/NVSourceHighlighter.m Sources/Editor/LinkingEditor.m
```

With `NV_CQ_BASELINE=1`, the fixture omits only six provisional-color assertions: two per language. All 127 common assertions remain enabled.

The baseline lost the unchanged token colors immediately after insertion in all three languages. The fixed application retained those colors in all three languages.

Both applications cleared the active editor's search backgrounds when editing began. Both retained the peer's previous query ranges until native query refresh. This behavior is pre-existing; it is not a regression introduced by retained syntax colors.

No fixture correction was needed. Both runs passed on their first attempt.

## Reproduction

Run the fixed application probe from the repository root:

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/SyntaxFlickerReview/round2/contrarian/checks.inc \
  --prefix Tests/SyntaxFlickerReview/round2/contrarian/prefix.h \
  --app build/SyntaxFlickerReview/fix.app
```

Run the common baseline control:

```sh
NV_CQ_BASELINE=1 python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/SyntaxFlickerReview/round2/contrarian/checks.inc \
  --prefix Tests/SyntaxFlickerReview/round2/contrarian/prefix.h \
  --app build/ViewControlsReview/round1/nvALT.app
```

The runner copies the application, isolates notes and preferences, and serializes desktop access through `build/pr-review/gui.lock`.

## Limits

These checks exercise native editing methods and drawing-delegate output. They do not use physical key events or measure display-frame timing.

Query refresh uses the actual search-highlight preference callback. The test does not claim that newly inserted query matches highlight automatically during typing.

The histories append characters and switch notes before the parser debounce runs. They do not force every worker completion order or test all query syntax.

No production change is proposed from this review.
