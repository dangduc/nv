# Round 1: persistence and lifetime histories

This review uses a Kyle Kingsbury-inspired perspective. It does not represent a review or statement by Kyle Kingsbury.

No actionable regression was found at `162c872`, compared with `b27af28`, in the histories below.

The probe passed 112 checks across two real app processes. The runner reused one disposable notes directory and one unique defaults domain.
The first process stored the window state through the application coordinator. The second process used the normal startup restoration path.

The histories covered these transitions:

- Two windows used separate expanded list heights of 120 and 180 points.
- Both windows hid the list, Title, Tags, body controls, and word count.
- A collapsed window became smaller, then returned to its original size.
- Relaunch preserved physical list collapse, hidden header rows, selected notes, and separate expanded heights.
- Show restored each physical divider to its saved height.
- Twenty interleaved histories changed visibility, created a collapsed window, closed that window, and restored the original lists.
- An old side-by-side window state converted its saved width into a vertical list height without revealing the hidden list.
- Library replacement preserved shared visibility and the original browser owners.

## Commands and evidence

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/ViewControlsReview/round1/kingsbury/probe.m \
  --app build/ViewControlsReview/round1/nvALT.app --launches 2
```

The command returned 0. `results.log` records 13 checks in phase 1 and 99 checks in phase 2.

The mutation control returned zero from `notesListHeight` for collapsed windows during coordinator serialization:

```sh
NV_REVIEW_ZERO_COLLAPSED_HEIGHT=1 python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/ViewControlsReview/round1/kingsbury/probe.m \
  --app build/ViewControlsReview/round1/nvALT.app --launches 2
```

The first process completed. The second process returned 1 at `relaunch preserves each window's saved expanded height while collapsed`.
`negative-control.log` records that failure. The mutation changed only the disposable process.

## Limits

The probe used macOS 26.5.2 and the Intel Development app under Rosetta. It did not simulate process crashes, disk errors, power loss, or concurrent external writes.

The twenty histories ran on the native UI thread. They included queued callbacks, but do not establish thread safety for calls from arbitrary threads.

Both temporary libraries used the same disposable bundle cache. The fixture closed the original journal before the replacement constructor opened its journal.
The report concerns view state across library replacement. It makes no claim about journal recovery across simultaneous library construction.
