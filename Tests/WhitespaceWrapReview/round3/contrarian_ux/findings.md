# Round 3: Contrarian UX perspective

No actionable finding.
The final copied app handles the original empty-note Space sequence without a backward caret jump in the queried geometry.
Backspace retraces every recorded insertion point, including nine observed wrap boundaries.

Frozen revision: `4b725372670afd5f5ecadf512deba8498336b2f0`.
This review challenges the visible-caret behavior after the buffer optimization in `LinkingEditor.m:286–324`.
Character wrapping remains the selected source policy.

## Executed evidence

The new actual-app probe passed 2,802 checks and delivered 1,644 key events through `NSApp`.
Each fixture starts with an empty plain-text note, an empty search field, and focus in the visible source editor.
Repeated Space and Backspace events set the native repeat flag after their first event.
The probe does not replace any production editor method.

Runtime implementation comparisons confirm that `LinkingEditor` inherits these three methods directly from `NSTextView`:

- `keyDown:`
- `insertText:replacementRange:`
- `deleteBackward:`

The probe records a caret rectangle after every repeated Space and every reversing Backspace.
It checks exact source contents and selection at each step.
The three fixtures produce these wrap thresholds:

| Font | Window content width | Space counts at forward wraps | Total spaces before reversal |
| --- | ---: | --- | ---: |
| Menlo 18 | 560 | 50, 99, 148 | 151 |
| Helvetica 14 | 470 | 117, 233, 349 | 352 |
| Menlo 26 | 620 | 38, 75, 112 | 115 |

For Menlo 18, Space 50 moves the caret from `(544.009, 8)` to `(23.837, 29)`.
The next two transitions follow the same horizontal pattern on later lines.
Every Backspace restores the preceding point within 0.02 points.
All three sequences return to an empty source and model.
The proportional and larger fonts also retain ordinary space advances after wrapping.

Each fixture then receives 100 mixed Space and `k` events.
Twelve subsequent cycles alternate window widths between 650 and 470 points.
Each cycle delivers two spaces and one `k` after resizing.
Source and logical selection remain unchanged during resize.
Following key events advance the caret within the new width and preserve exact source and model contents.

Finally, three native mouse-down/up sequences select positions on wrapped lines.
The selected indexes are exactly 44, 94, and 32 for the three respective fixtures.
Those clicks do not change source text.

## Reproduce

```sh
python3 Tests/WhitespaceWrapReview/round3/contrarian_ux/run.py
```

Host: macOS 26.5.2 (25F84), Intel app under Rosetta.
Executable SHA-256: `55f97d1af69d120f385698b428a616e473be020200d3fe0ebcc6b626253459be`.
`results.json` records the binary and check count.
`typing-results.json` contains exact thresholds, geometry, mouse selections, and key count.
The full generated log is in `build/WhitespaceWrapReview/round3/contrarian_ux/candidate.log`.

The launcher and native caret helpers are reused from earlier reviews; these empty-note typing sequences and reverse traces are new.
The runner uses an isolated copied app, disposable notes, a unique preference domain, and the shared GUI lock.

## Limits

The probe supplies synthetic native events and queries `firstRectForCharacterRange:actualRange:` synchronously.
Those queries can force TextKit layout.
This measures insertion geometry, not every painted caret frame during physical key repeat.
It does not establish behavior on the user's macOS 13 host or under that host's event timing.
The mouse checks cover single clicks, not drag-selection tracking or physical pointer movement.
The fixtures use left-to-right plain text and do not cover input-method composition.
