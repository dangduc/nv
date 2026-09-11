#!/usr/bin/env python3
"""Compare native whitespace layout settings using disposable NSTextViews."""
import argparse
import json
from pathlib import Path
import platform
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--arch", choices=("arm64", "x86_64"), default=platform.machine())
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
output = repo / "build/WhitespaceWrapping"
output.mkdir(parents=True, exist_ok=True)
binary = output / f"probe-{args.arch}"
result = output / f"results-{args.arch}.json"
subprocess.run([
    "xcrun", "clang", "-arch", args.arch, "-mmacosx-version-min=13.0",
    "-fno-objc-arc", "-Wno-deprecated-declarations", "-framework", "Cocoa",
    str(Path(__file__).with_name("probe.m")), "-o", str(binary),
], check=True)
subprocess.run(["arch", f"-{args.arch}", str(binary), str(result)], check=True, timeout=90)
rows = json.loads(result.read_text())
by_case = {(r["mode"], r["fontSize"], r["fixture"]): r for r in rows}
for size in (12, 22):
    for fixture in ("prose", "tabs", "unicode"):
        native = by_case["default", size, fixture]["before"]
        fixed = by_case["fixed-space-glyphs", size, fixture]["before"]
        assert native["lines"] == fixed["lines"], (size, fixture, "unexpected baseline layout change")
    for fixture in ("spaces", "prefix-spaces", "unicode-spaces", "repeated-key-events"):
        fixed = by_case["fixed-space-glyphs", size, fixture]["afterSpace"]
        assert len(fixed["lines"]) > 1, (size, fixture, "spaces did not wrap")
        assert fixed["validCaretRect"] and fixed["caretY"] > 8, (size, fixture, "caret did not advance")
    fixed = by_case["fixed-space-glyphs", size, "repeated-key-events"]
    assert fixed["afterBackspace"]["caretX"] < fixed["afterSpace"]["caretX"]
print("PASS: layout comparisons, whitespace wrapping, and caret advancement")
print("mode | font | lines after 201 Space keys | caret x | caret y | horizontal scroll")
for row in rows:
    if row["fixture"] == "repeated-key-events":
        state = row["afterSpace"]
        print(f'{row["mode"]} | {row["fontSize"]} | {len(state["lines"])} | '
              f'{state["caretX"]} | {state["caretY"]} | {state["visibleX"]}')
print(result)
