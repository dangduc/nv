#!/usr/bin/env python3
"""Actual frozen correction versus pre-fix source; compact timing and work proof."""
from pathlib import Path
import hashlib
import json
import platform
import statistics
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = "2ea92180939a3e51df8fe867ad548140ed455868"
HEAD = "e022109eaf2bad6583512c2ed2b48561d9dae011"


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
assert typesetter == source(BASE, "Sources/Editor/NVSourceTypesetter.m")
header = source(HEAD, "Sources/Editor/NVSourceTypesetter.h")
assert header == source(BASE, "Sources/Editor/NVSourceTypesetter.h")
support = source(HEAD, "Tests/WrappedSeparatorReview/round1/luu/probe.m")
support = support[:support.index("static NSArray *Fixtures(void)")]
report = {"head": HEAD, "base": BASE, "typesetter_unchanged": True, "macos": subprocess.check_output(["sw_vers", "-productVersion"], text=True).strip(), "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(), "host_architecture": platform.machine(), "binary_architecture": "x86_64", "compiler_flags": "-O2 -fno-objc-arc -fblocks -mmacosx-version-min=10.13", "delegate_sha256": {ref: hashlib.sha256(delegate(ref).encode()).hexdigest() for ref in (BASE, HEAD)}, "method": {"count_trials": 1, "timing_trials": 5, "discarded_trials": 1, "paired_order": "(trial + order) % 2", "start_pair_edits": 2, "font": "Menlo-Regular 16", "container_width_points": 544, "geometry_comparison": "exact glyph-position and line-rectangle bytes; property hash and line coverage; initial, inserted, restored states"}}
raw = {}
with tempfile.TemporaryDirectory(prefix="probe-", dir=HERE) as temporary:
    temp = Path(temporary)
    (temp / "NVSourceTypesetter.h").write_text(header)
    for mode in ("counts", "timing"):
        code = support
        for token, ref in (("@BASE_DELEGATE@", BASE), ("@CANDIDATE_DELEGATE@", HEAD)):
            implementation = delegate(ref)
            if mode == "counts":
                implementation = implementation.replace("[source rangeOfComposedCharacterSequenceAtIndex:index]", "CountComposed(source, index)")
            code = code.replace(token, implementation)
        (temp / "support.m").write_text(code.replace("@TYPESETTER@", typesetter))
        binary = temp / mode
        build = subprocess.run(["xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13", "-O2", "-fno-objc-arc", "-fblocks", "-Wno-deprecated-declarations", *(["-DCOUNTS=1"] if mode == "counts" else []), "-I", str(temp), "-framework", "Cocoa", "-framework", "CoreText", str(HERE / "probe.m"), "-o", str(binary)], capture_output=True, text=True, timeout=60)
        build.check_returncode()
        output = temp / (mode + ".json")
        run = subprocess.run([str(binary), str(output)], capture_output=True, text=True, timeout=100)
        (HERE / (mode + ".log")).write_text(build.stdout + build.stderr + run.stdout + run.stderr)
        print(mode + ": " + run.stdout + run.stderr, end="", flush=True)
        run.check_returncode()
        raw[mode] = json.loads(output.read_text())
report["checks"] = {mode: data["checks"] for mode, data in raw.items()}
report["geometry_equivalence_passed"] = True
report["cases"] = []
counts = {(row["fixture"], row["operation"], row["variant"]): row for row in raw["counts"]["records"]}
work_fields = ["glyph_callbacks", "glyphs_visited", "composed_queries", "explicit_buffer_allocations", "explicit_buffer_bytes", "typesetter_creates", "snapshot_characters", "cluster_suggestions", "line_creates", "token_advances"]
for fixture, operation in dict.fromkeys((row["fixture"], row["operation"]) for row in raw["counts"]["records"]):
    case = {"fixture": fixture, "operation": operation}
    for variant in ("pre-fix", "fixed"):
        samples = [row for row in raw["timing"]["records"] if row["fixture"] == fixture and row["operation"] == operation and row["variant"] == variant]
        measured = counts[fixture, operation, variant]
        case["characters"] = measured["characters"]
        case[variant] = {"wall_ms": [round(row["wall_ms"], 6) for row in samples], "delegate_ms": [round(row["delegate_ms"], 6) for row in samples], "counts": {key: measured[key] for key in work_fields}}
        for key in ("wall_ms", "delegate_ms"):
            case[variant]["median_" + key] = statistics.median(case[variant][key][1:])
    case["saved_wall_ms"] = case["pre-fix"]["median_wall_ms"] - case["fixed"]["median_wall_ms"]
    case["saved_delegate_ms"] = case["pre-fix"]["median_delegate_ms"] - case["fixed"]["median_delegate_ms"]
    comparable = [key for key in work_fields if key != "composed_queries"]
    case["other_work_counts_equal"] = all(case["pre-fix"]["counts"][key] == case["fixed"]["counts"][key] for key in comparable)
    assert case["other_work_counts_equal"], case
    if fixture.startswith("ascii-"):
        assert case["pre-fix"]["counts"]["composed_queries"] > 0 and case["fixed"]["counts"]["composed_queries"] == 0
    else:
        assert case["fixed"]["counts"]["composed_queries"] > 0
    report["cases"].append(case)
    print(f"{fixture} {operation}: {case['pre-fix']['median_wall_ms']:.3f} -> {case['fixed']['median_wall_ms']:.3f} ms; saved {case['saved_wall_ms']:.3f} ms", flush=True)
report["result"] = "PASS: P3 query elimination is present in the actual correction; no other measured work amplification or geometry/source change"
(HERE / "results.json").write_text(json.dumps(report, indent=2) + "\n")
assert sum(path.stat().st_size for path in HERE.iterdir() if path.is_file()) < 100 * 1024
print(report["result"])
