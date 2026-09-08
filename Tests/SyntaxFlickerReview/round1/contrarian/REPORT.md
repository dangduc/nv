# Round 1: contrarian review

No actionable defect introduced by PR #6 was found in this scope.

This review challenges whether retained syntax colors conflict with native editor appearance or editing behavior. The reviewed production revision is `65e1608`. The PR base is `8cd2c95`.

## Evidence

The native fixture passed **109 checks** in a copied application with disposable notes. See [checks.inc](checks.inc), [prefix.h](prefix.h), and [output.txt](output.txt).

Six histories covered Markdown, HTML, and JSON with both dark and light editor colors. Each history used two source windows for one note.

The checks called the actual layout drawing delegate. They did not infer visible colors from raw syntax capture attributes.

- An unaffected token retained its drawn syntax color immediately after a native insertion, while semantic captures were obsolete.
- The native link detector recognized each URL. Link foreground colors took precedence over provisional syntax colors.
- Separate temporary search backgrounds survived the drawing delegate in both windows while syntax remained provisional.
- Private capture attributes did not reach the drawing result or note model.
- Native Undo and Redo preserved the exact source. Both windows received current captures after analysis completed.
- Native marked-text input retained the heading color outside the composition.
- An overlapping temporary syntax capture did not replace the composition's foreground or underline. The effective drawing range stayed inside the marked range.
- Committing the composition preserved its exact source text.

The marked-range overlap was an adversarial display fixture. It installed a temporary capture after native composition began, outside character processing. The composition itself used `setMarkedText:selectedRange:replacementRange:`.

## Controls and fixture corrections

The same full fixture failed against the pre-fix application at the first assertion for retained drawn syntax color. See [negative-control-base.txt](negative-control-base.txt). This negative control detects the original defect.

The baseline application came from `build/ViewControlsReview/round1/nvALT.app`, built at `162c872`. Its highlighter and editor source match PR base `8cd2c95`. The comparison used:

```sh
git diff 162c872 8cd2c95 -- Sources/Editor/NVSourceHighlighter.m Sources/Editor/LinkingEditor.m
```

The comparison had no differences.

An initial fixture manually installed search backgrounds before insertion, without an actual search query. Native edit refresh removed those backgrounds. An identical control reproduced this removal in both applications. See [search-control.inc](search-control.inc), [search-control-base.txt](search-control-base.txt), and [search-control-head.txt](search-control-head.txt).

The corrected fixture installs backgrounds after insertion, while analysis remains pending. This checks drawing precedence without assuming manual highlights survive search refresh. The original assertion failure remains in [initial-search-fixture-output.txt](initial-search-fixture-output.txt).

The first launch used a nonexistent controller accessor. The disposable app was terminated, and the fixture used `sharedNotationController` instead. The compiler warning and partial output remain in [initial-fixture-output.txt](initial-fixture-output.txt).

## Reproduction

Run the fixture from the repository root:

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/SyntaxFlickerReview/round1/contrarian/checks.inc \
  --prefix Tests/SyntaxFlickerReview/round1/contrarian/prefix.h \
  --app build/SyntaxFlickerReview/fix.app
```

The runner copies the app, isolates notes and preferences, and serializes desktop access through `build/pr-review/gui.lock`.

## Limits

These checks cover drawing-delegate output, not rendered bitmaps or display-frame timing. Dark and light cases use application foreground and background preferences. They do not exercise every system appearance transition.

The fixture uses native composition APIs, not a physical keyboard or an installed input method. Search-background checks use controlled temporary attributes. They do not cover the complete search interaction.

No production change is proposed from this review.
