# Display budget follow-up

The highlighter now checks a separate display budget before applying a revision.
The capture count multiplied by the attached layout count must fit within 4,096 capture writes.
Larger results display plain source in all layouts, while retaining the parsed result for later layout changes.
Layouts without a capture revision skip temporary-attribute removal.
Character edits still invalidate revisions immediately and defer TextKit changes until character processing finishes.

The production regression harness passed 345 checks on September 8, 2026.
New checks count actual `addTemporaryAttribute:value:forCharacterRange:` calls.
An 800-capture HTML result makes 3,200 writes across four layouts and zero across twenty layouts.
Removing the extra layouts restores all 3,200 writes.
The 24,000-capture review fixture makes zero writes across four or twenty layouts.
Source attributes and independent search backgrounds remain intact.

The original latency probe produced [fixed-measurements.csv](fixed-measurements.csv) with the patched production highlighter.
The historical [measurements.csv](measurements.csv) remains unchanged.

| HTML fixture | Layouts | Historical first apply | Fixed first apply | Fixed display |
| --- | ---: | ---: | ---: | --- |
| 90,780 UTF-16 units, 24,000 captures | 4 | 246.051ms | <0.001ms | Plain |
| 90,780 UTF-16 units, 24,000 captures | 20 | 1,234.319ms | <0.001ms | Plain |
| 2,680 UTF-16 units, 800 captures | 4 | 1.397ms | 1.332ms | Highlighted |

The fixed large HTML parse took 78.032ms and produced all 24,000 captures.
The display budget independently rejected those captures before the main-thread application loop.
Values below 0.001ms reflect the CSV measurement precision.
This probe excludes glyph layout, painting, and end-to-end typing latency.
The operation limit is not a wall-clock guarantee for those activities.

Run the regression harness from the repository root:

```sh
python3 Tests/Regression/source-highlighting/run.py
```

To repeat the original timing probe without replacing its historical CSV:

```sh
python3 - <<'PY'
from pathlib import Path
path = Path('Tests/SourceViewerReview/round1/dan_luu/run.py').resolve()
source = path.read_text().replace("'measurements.csv'", "'fixed-measurements.csv'")
exec(compile(source, str(path), 'exec'), {'__file__': str(path), '__name__': '__main__'})
PY
```
