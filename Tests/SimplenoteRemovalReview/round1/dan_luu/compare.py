#!/usr/bin/env python3
"""Compare operation counts from the paired native storage experiment."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent
pattern = re.compile(r"DAN_CYCLE app=(\w+) cycle=(\d+) snapshotWrites=(\d+) snapshotBytes=(\d+) journalWrites=(\d+) encodedNotes=(\d+) decodedNotes=(\d+) liveDecoded=(\d+) databaseBytes=(\d+) unchanged=(\d+)")
names = ("cycle", "snapshotWrites", "snapshotBytes", "journalWrites", "encodedNotes", "decodedNotes", "liveDecoded", "databaseBytes", "unchanged")
rows = {}
for app in ("baseline", "current"):
    log = (root / f"{app}.log").read_text()
    rows[app] = [dict(zip(names, map(int, match.groups()[1:]))) for match in pattern.finditer(log)]
    assert "FAIL" not in log and f"DAN_RESULT app={app} checks=83 cycles=8 notes=1024" in log
    assert len(rows[app]) == 8

for before, after in zip(rows["baseline"], rows["current"]):
    for name in ("cycle", "snapshotWrites", "journalWrites", "encodedNotes", "decodedNotes", "liveDecoded"):
        assert before[name] == after[name], (name, before, after)
    assert after["databaseBytes"] < before["databaseBytes"]
    assert after["unchanged"] == (after["cycle"] not in (0, 4))
    assert before["unchanged"] == (before["cycle"] != 4)

first_before, first_after = rows["baseline"][0], rows["current"][0]
print("PASS: 8 paired cycles; snapshot, journal, encode, decode, and live-decoded counts match in every cycle")
print("PASS: 83 native checks per app preserve all 1,024 notes and their local source metadata")
print("PASS: archive bytes change only for first migration and the 64-note edit, then remain stable")
print(f"First snapshot bytes: {first_before['databaseBytes']} -> {first_after['databaseBytes']} ({first_before['databaseBytes'] - first_after['databaseBytes']} fewer)")
for app in ("baseline", "current"):
    print(f"{app}: snapshots={sum(row['snapshotWrites'] for row in rows[app])}; journal records={sum(row['journalWrites'] for row in rows[app])}; final tracked live decoded notes={rows[app][-1]['liveDecoded']}")
