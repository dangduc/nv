#!/usr/bin/env python3
"""Check paired native write counts and the real-writer sensitivity control."""
from pathlib import Path
import re

here = Path(__file__).resolve().parent
pattern = re.compile(
    r"DAN_R2_PHASE name=(\S+) files=(\d+) journal=(\d+) snapshots=(\d+) physical=(\d+)"
)
expected = [
    ("insert-burst", 8, 8, 1, 8),
    ("unchanged-after-insert", 0, 0, 0, 0),
    ("delete-burst", 8, 8, 1, 8),
    ("unchanged-after-delete", 0, 0, 0, 0),
    ("selection-only", 0, 8, 1, 8),
    ("tags-only", 8, 8, 1, 8),
    ("syntax-only", 0, 0, 1, 0),
    ("idle-source-save", 1, 1, 0, 1),
    ("snapshot-after-idle", 0, 0, 1, 0),
    ("final-unchanged", 0, 0, 0, 0),
]
paired = []
for app in ("baseline", "current"):
    text = (here / f"{app}.log").read_text()
    assert "FAIL" not in text, app
    rows = [(name, *(int(value) for value in values))
            for name, *values in pattern.findall(text)]
    assert rows == expected, (app, rows)
    assert re.search(rf"DAN_R2_RESULT app={app} .*phases=10 checks=78", text)
    totals = tuple(sum(row[index] for row in rows) for index in range(1, 5))
    assert totals == (25, 33, 6, 33), totals
    paired.append(rows)
    print(f"PASS {app}: 10 phases, 78 native checks, files/journal/snapshots/physical={totals}")
assert paired[0] == paired[1]
control = (here / "unbatched-control.log").read_text()
assert "FAIL: 320 source commits queue without synchronous persistence" in control
assert "DAN_R2_RESULT" not in control
print("PASS paired counts match; immediate real-writer mutation fails the intended batching assertion")
