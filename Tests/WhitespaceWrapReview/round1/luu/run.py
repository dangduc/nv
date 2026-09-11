#!/usr/bin/env python3
"""Time the exact production glyph delegate on native TextKit-generated batches."""
import fcntl
import json
from pathlib import Path
import subprocess

here = Path(__file__).resolve().parent
repo = here.parents[3]
out = repo / "build/WhitespaceWrapReview/round1/luu"
out.mkdir(parents=True, exist_ok=True)
source = (repo / "Sources/Editor/LinkingEditor.m").read_text()
start = source.index("- (NSUInteger)layoutManager:(NSLayoutManager *)manager shouldGenerateGlyphs:")
end = source.index("\n- (NSColor *)sourceColorForCapture:", start)
method = source[start:end]
assert "malloc(range.length * sizeof(NSGlyphProperty))" in method
generated = (here / "probe.m").read_text().replace("/* PRODUCTION_METHOD */", method)
(out / "probe-generated.m").write_text(generated)
binary = out / "probe"
subprocess.run(["xcrun", "clang", "-arch", "x86_64", "-O2", "-fno-objc-arc",
                "-mmacosx-version-min=10.13", "-Wno-deprecated-declarations",
                "-framework", "Cocoa", str(out / "probe-generated.m"), "-o", str(binary)], check=True)
lock_path = Path("/Users/duc/dev/nv/build/pr-review/gui.lock")
lock_path.parent.mkdir(parents=True, exist_ok=True)
with lock_path.open("a") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    completed = subprocess.run(["arch", "-x86_64", str(binary), str(out / "results.json")],
                               capture_output=True, text=True, timeout=240, check=True)
print(completed.stdout, end="")
print(completed.stderr, end="")
rows = json.loads((out / "results.json").read_text())
assert len(rows) == 540, len(rows)
for row in rows:
    assert row["unchangedSource"]
    if row["stage"] == "resize":
        assert row["stats"]["callbacks"] == 0, row
    if row["mode"] == "adjusted":
        assert row["stats"]["allocations"] == row["stats"]["changedBatches"], row
        assert row["stats"]["maxAllocationBytes"] <= row["stats"]["maxBatch"] * 8, row
    else:
        assert row["stats"]["allocations"] == 0, row
for size in ("201", "4k", "32k"):
    for width in (160, 480):
        controls = [r for r in rows if r["fixture"] == "letters-" + size and
                    r["mode"] == "native" and r["stage"] == "initial" and r["width"] == width]
        adjusted = [r for r in rows if r["fixture"] == "spaces-" + size and
                    r["mode"] == "adjusted" and r["stage"] == "initial" and r["width"] == width]
        assert [r["lines"] for r in adjusted] == [r["lines"] for r in controls], (size, width)
# Keep full trials in the ignored output tree; commit compact median measurements.
import statistics
summary = []
for key in sorted({(r["fixture"], r["width"], r["stage"], r["mode"]) for r in rows}):
    group = [r for r in rows if (r["fixture"], r["width"], r["stage"], r["mode"]) == key]
    first = group[0]
    summary.append({"fixture":key[0], "width":key[1], "stage":key[2], "mode":key[3],
                    "ms":round(statistics.median(r["ms"] for r in group), 6),
                    "lines":first["lines"],
                    "stats":{k:round(statistics.median(r["stats"][k] for r in group), 6)
                             for k in first["stats"]}})
(here / "results.json").write_text(json.dumps(summary, indent=2) + "\n")
print("PASS: 540 measured stages, source preserved, no glyph regeneration during resize, one allocation per changed batch")
print("PASS: wrapped-space initial line counts match same-length native x controls")
visible = json.loads((out / "results.json.visible.json").read_text())
assert len(visible) == 270
assert all(r["unchangedSource"] for r in visible)
summary = []
for key in sorted({(r["length"], r["initialWidth"], r["stage"], r["mode"]) for r in visible}):
    group = [r for r in visible if (r["length"], r["initialWidth"], r["stage"], r["mode"]) == key]
    first = group[0]
    summary.append({"length":key[0],"initialWidth":key[1],"stage":key[2],"mode":key[3],
        "width":first["width"], "ms":round(statistics.median(r["ms"] for r in group),6),
        "laidCharacters":first["laidCharacters"],
        "callbackMs":round(statistics.median(r["stats"]["callbackMs"] for r in group),6)})
(here / "visible-results.json").write_text(json.dumps(summary,indent=2)+"\n")
print("PASS: 270 bounded-visible, width-reflow, and end-caret stages preserve source")
