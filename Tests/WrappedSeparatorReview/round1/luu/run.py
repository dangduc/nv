#!/usr/bin/env python3
"""Paired frozen TextKit layout timings and separately instrumented work counts."""
from pathlib import Path
import json
import platform
import statistics
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = "75d6f42"
HEAD = "9e6c8dd6adc058e7044f2c562532af97dd4e63d4"


def source(ref, path):
    return subprocess.check_output(["git", "show", f"{ref}:{path}"], cwd=ROOT, text=True)


def delegate(ref):
    text = source(ref, "Sources/Editor/LinkingEditor.m")
    start = text.index("- (NSUInteger)layoutManager:")
    end = text.index("{", start) + 1
    depth = 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]


typesetter = source(HEAD, "Sources/Editor/NVSourceTypesetter.m")
header = source(HEAD, "Sources/Editor/NVSourceTypesetter.h")
assert typesetter == source(BASE, "Sources/Editor/NVSourceTypesetter.m")
assert header == source(BASE, "Sources/Editor/NVSourceTypesetter.h")
report = {"base": subprocess.check_output(["git", "rev-parse", BASE], cwd=ROOT, text=True).strip(), "head": HEAD, "environment": subprocess.check_output(["sw_vers"], text=True).strip(), "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(), "host_architecture": platform.machine(), "binary_architecture": "x86_64", "typesetter_unchanged": True}
with tempfile.TemporaryDirectory(prefix="probe-", dir=HERE) as temporary:
    temp = Path(temporary)
    (temp / "NVSourceTypesetter.h").write_text(header)
    for mode in ("counts", "timing"):
        base, candidate = delegate(BASE), delegate(HEAD)
        if mode == "counts":
            candidate = candidate.replace("[source rangeOfComposedCharacterSequenceAtIndex:index]", "CountComposed(source, index)")
        code = (HERE / "probe.m").read_text().replace("@BASE_DELEGATE@", base).replace("@CANDIDATE_DELEGATE@", candidate).replace("@TYPESETTER@", typesetter)
        generated = temp / (mode + ".m")
        generated.write_text(code)
        binary = temp / mode
        build = subprocess.run(["xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13", "-O2", "-fno-objc-arc", "-fblocks", "-Wno-deprecated-declarations", *(["-DCOUNTS=1"] if mode == "counts" else []), "-I", str(temp), "-framework", "Cocoa", "-framework", "CoreText", str(generated), "-o", str(binary)], capture_output=True, text=True, timeout=60)
        (HERE / (mode + "-compile.log")).write_text(build.stdout + build.stderr)
        build.check_returncode()
        output = HERE / (mode + ".json")
        run = subprocess.run([str(binary), str(output)], capture_output=True, text=True, timeout=90)
        (HERE / (mode + "-run.log")).write_text(run.stdout + run.stderr)
        print(mode, run.stdout + run.stderr, end="", flush=True)
        run.check_returncode()
        report[mode] = json.loads(output.read_text())
summary = []
rows = report["timing"]["records"]
for fixture in dict.fromkeys(row["fixture"] for row in rows):
    for operation in ("initial", "incremental"):
        medians = {}
        for variant in ("base", "candidate"):
            samples = [row for row in rows if row["fixture"] == fixture and row["operation"] == operation and row["variant"] == variant and row["trial"] > 0]
            medians[variant] = {key: statistics.median(row[key] for row in samples) for key in ("wall_ms", "delegate_ms")}
        summary.append({"fixture": fixture, "operation": operation, "median_ms": medians, "candidate_minus_base_ms": medians["candidate"]["wall_ms"] - medians["base"]["wall_ms"], "candidate_to_base_ratio": medians["candidate"]["wall_ms"] / medians["base"]["wall_ms"]})
report["summary"] = summary
(HERE / "results.json").write_text(json.dumps(report, indent=2) + "\n")
for row in summary:
    print(row["fixture"], row["operation"], row["median_ms"], flush=True)
print("PASS: frozen delegates/current typesetter, source preservation, incremental restoration, cached layout, and bounded work samples")
