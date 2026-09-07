# Validation on September 7, 2026

The host ran macOS 13.7.8 with Xcode 15.2 and the macOS 14.2 SDK. The app used an Intel Development build under Rosetta.

## Results

- The Development build completed.
- `Tests/run-multiple-windows-tests.py` passed 35 checks and 13 relaunch checks.
- `Tests/run-regression-tests.py` passed all checks, including 41 native UI checks and the ownership and restoration mutations.
- Light and dark snapshots showed both panes across the window width, with the list above the editor.

## Performance sample

The comparison used the merged baseline `116daff` and the native UI build. Both runs used 10,000 generated notes and a 640-by-160-point table viewport.

| Operation | Baseline median / p95 | Native UI median / p95 |
| --- | --- | --- |
| Four filter queries | 62.55 / 64.84 ms | 61.44 / 64.33 ms |
| Scroll and table bitmap capture | 17.14 / 31.04 ms | 18.54 / 34.39 ms |

The fixture used 30 query sequences and 60 scroll operations. These measurements represent one run per build. Bitmap capture includes capture costs and does not measure animation frame rate.

## Remaining manual checks

The desktop session was locked. Full-screen transitions failed in both nvALT and an isolated stock Cocoa window because neither app became active. The optional full-screen test requires an unlocked desktop session.

Ventura logged a layout warning during `NSSearchToolbarItem` layout. An LLDB trace placed the recursive layout call inside AppKit toolbar constraints. The resize and control checks passed despite this warning.

Live sync services, external editor applications, and other macOS versions were not exercised.
