#!/usr/bin/env python3
"""Check recorded original-object and serialization counts from three real-app runs."""
from pathlib import Path

root = Path(__file__).resolve().parent


def batches(filename):
    log = (root / filename).read_text()
    rows = []
    for line in log.splitlines():
        if "DAN_R3_BATCH " not in line:
            continue
        pairs = dict(item.split("=", 1) for item in line.split("DAN_R3_BATCH ", 1)[1].split())
        rows.append({key: int(value) for key, value in pairs.items() if key != "app"})
    assert len(rows) == 4, (filename, len(rows))
    assert "DAN_R3_RESULT " in log and "FAIL" not in log, filename
    return rows


old = batches("baseline.log")
new = batches("current.log")
local = batches("baseline-no-remote.log")
for index, (before, after, disabled) in enumerate(zip(old, new, local), 1):
    common = {
        "batch": index, "created": index * 24, "survivors": index * 6,
        "noteRecords": 78, "removalRecords": 48, "snapshotNotes": index * 6, "snapshots": index,
    }
    assert before == dict(common, released=0, liveOriginals=index * 24, snapshotTombstones=index * 18)
    assert after == dict(common, released=index * 18, liveOriginals=index * 6, snapshotTombstones=0)
    assert disabled == after
    print(f"PASS batch {index}: 126 local journal records; {index * 6} surviving source records; "
          f"PR releases {index * 18} deleted originals and omits their remote tombstones")

failure = "FAIL: drained pools leave only the expected original notes retained after Undo is cleared"
for name in ("retention-control.log", "baseline-constructor-tags-control.log"):
    text = (root / name).read_text()
    assert failure in text and "DAN_R3_RESULT " not in text, name
    print(f"PASS expected control failure: {name}")
print("PASS: all paired counts match; baseline without remote metadata equals PR")
