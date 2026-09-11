#!/usr/bin/env python3
"""Run native paragraph geometry against the production typesetter."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
OUTPUT = ROOT / "build/WordWrapReview/round1/torvalds"
OUTPUT.mkdir(parents=True, exist_ok=True)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--arch", choices=["arm64", "x86_64"], default="arm64")
parser.add_argument("--negative-control", action="store_true")
args = parser.parse_args()
source = (ROOT / "Sources/Editor/LinkingEditor.m").read_text()
start = source.index("- (NSUInteger)layoutManager:")
opening = source.index("{", start)
depth, end = 1, opening + 1
while depth:
    depth += (source[end] == "{") - (source[end] == "}")
    end += 1
delegate = source[start:end]
(OUTPUT / "production-space-delegate.h").write_text(
    "@interface SpaceDelegate : NSObject <NSLayoutManagerDelegate>\n@end\n"
    "@implementation SpaceDelegate\n" + delegate + "\n@end\n")
binary = OUTPUT / f"probe-{args.arch}"
subprocess.run([
    "xcrun", "clang", "-arch", args.arch,
    f"-mmacosx-version-min={'11.0' if args.arch == 'arm64' else '10.13'}",
    "-fno-objc-arc", "-Wno-deprecated-declarations", "-Wall", "-Wextra", "-Wno-unused-parameter",
    "-framework", "Cocoa", "-framework", "CoreText", "-I", str(OUTPUT),
    "-I", str(ROOT / "Sources/Editor"), str(Path(__file__).with_name("probe.m")),
    str(ROOT / "Sources/Editor/NVSourceTypesetter.m"), "-o", str(binary)
], check=True)
label = args.arch + ("-negative" if args.negative_control else "")
evidence = OUTPUT / f"geometry-{label}.json"
command = ["arch", f"-{args.arch}", str(binary), str(evidence)]
if args.negative_control:
    command.append("negative")
subprocess.run(command, check=True, timeout=120)
results = json.loads(evidence.read_text())
differences = []
split_words = []
comparisons = 0
previous_splits = 0
for case in results:
    c, r = case["candidate"], case["reference"]
    assert c["unchanged"] and r["unchanged"]
    for left, right in zip(c["lines"], r["lines"]):
        if (left["start"], left["length"]) != (right["start"], right["length"]):
            continue
        comparisons += len(left["points"])
        delta = max(abs(p[0] - q[0]) for p, q in zip(left["points"], right["points"]))
        if delta > .1:
            differences.append({k:case[k] for k in ["source", "width", "geometry", "alignment"]} |
                {"line":left["text"], "start":left["start"], "delta":delta,
                 "actual":left["used"], "expected":right["used"]})
    if case["source"].isascii():
        starts = {line["start"] for line in c["lines"]}
        for word in re.finditer(r"[A-Za-z]+", case["source"]):
            if any(word.start() < line["start"] < word.end() for line in case["previous"]["lines"]):
                previous_splits += 1
            if any(word.start() < start < word.end() for start in starts):
                split_words.append({k:case[k] for k in ["source", "width", "geometry", "alignment"]} |
                    {"word":word.group(), "lines":[line["text"] for line in c["lines"]],
                     "nativeLines":[line["text"] for line in r["lines"]]})
summary = {"cases":len(results), "same_line_geometry_differences":differences,
    "split_words":split_words, "matching_glyph_comparisons":comparisons, "previous_split_words":previous_splits,
    "commit":subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
    "productionSHA256":hashlib.sha256((ROOT / "Sources/Editor/NVSourceTypesetter.m").read_bytes()).hexdigest()}
supported = lambda case: case["geometry"] == "plain" and case["alignment"] != 3
supported_differences = [item for item in differences if supported(item)]
supported_splits = [item for item in split_words if supported(item)]
summary["source_geometry_differences"] = len(supported_differences)
summary["source_split_words"] = len(supported_splits)
(OUTPUT / f"summary-{label}.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2)+"\n")
if args.negative_control:
    assert supported_splits, "The previous character layout must fail the fitting-word condition."
else:
    assert not supported_splits, supported_splits
    assert not supported_differences, supported_differences
print(json.dumps({"cases":len(results), "geometryDifferences":len(differences), "splitWords":len(split_words)}))
for item in differences[:8] + split_words[:8]:
    print(json.dumps(item, ensure_ascii=False))
print("PASS negative control" if args.negative_control else "PASS default source geometry and fitting words")
