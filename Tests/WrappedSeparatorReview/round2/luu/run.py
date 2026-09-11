#!/usr/bin/env python3
"""Bounded large-paragraph review, with compact output and frozen production."""
from pathlib import Path
import hashlib
import json
import platform
import statistics
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = "75d6f42"
HEAD = "2ea92180939a3e51df8fe867ad548140ed455868"


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
assert delegate(HEAD) == delegate("9e6c8dd6adc058e7044f2c562532af97dd4e63d4")
# Reuse the committed, frozen R1 text-system/observer scaffolding, not its cases.
support = source(HEAD, "Tests/WrappedSeparatorReview/round1/luu/probe.m")
support = support[:support.index("static NSArray *Fixtures(void)")]
support = support.replace("static NSUInteger Checks,", "static NSUInteger StorageEdits, StorageInvalidated, StorageChanged;\nstatic NSUInteger Checks,")
support = support.replace("static void Reset(void) {", "static void Reset(void) { StorageEdits=StorageInvalidated=StorageChanged=0;")
support = support.replace('@{@"wall_ms":@(elapsed)', '@{@"storage_edit_callbacks":@(StorageEdits),@"storage_invalidated_units":@(StorageInvalidated),@"storage_changed_units":@(StorageChanged),@"wall_ms":@(elapsed)')
tracing = '''
@interface TraceLayout : NSLayoutManager @end
@implementation TraceLayout
- (void)processEditingForTextStorage:(NSTextStorage *)storage edited:(NSTextStorageEditActions)mask range:(NSRange)range changeInLength:(NSInteger)delta invalidatedRange:(NSRange)invalidated {
#ifdef COUNTS
    StorageEdits++; StorageChanged+=range.length; StorageInvalidated+=invalidated.length;
#endif
    [super processEditingForTextStorage:storage edited:mask range:range changeInLength:delta invalidatedRange:invalidated];
}
@end
'''
support = support.replace("@interface System : NSObject", tracing + "\n@interface System : NSObject")
support = support.replace("layout=[NSLayoutManager new]", "layout=[TraceLayout new]")
report = {"head": HEAD, "base": subprocess.check_output(["git", "rev-parse", BASE], cwd=ROOT, text=True).strip(), "macos": subprocess.check_output(["sw_vers", "-productVersion"], text=True).strip(), "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(), "host_architecture": platform.machine(), "binary_architecture": "x86_64", "typesetter_identical": True, "production_unchanged_since_round1": True, "compiler_flags": "-O2 -fno-objc-arc -fblocks -mmacosx-version-min=10.13", "support_sha256": hashlib.sha256(support.encode()).hexdigest(), "method": {"timing_trials": 5, "discarded_trials": 1, "paired_order": "(trial + order) % 2", "count_trials": 1, "edits_per_pair": 2, "short_paragraph_units": 256, "container_width_points": 544, "font": "Menlo-Regular 16"}}
raw = {}
with tempfile.TemporaryDirectory(prefix="probe-", dir=HERE) as temporary:
    temp = Path(temporary)
    (temp / "NVSourceTypesetter.h").write_text(source(HEAD, "Sources/Editor/NVSourceTypesetter.h"))
    for mode in ("counts", "timing"):
        candidate = delegate(HEAD)
        if mode == "counts":
            candidate = candidate.replace("[source rangeOfComposedCharacterSequenceAtIndex:index]", "CountComposed(source, index)")
        generated = support.replace("@BASE_DELEGATE@", delegate(BASE)).replace("@CANDIDATE_DELEGATE@", candidate).replace("@TYPESETTER@", typesetter)
        (temp / "support.m").write_text(generated)
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
counts = {(row["fixture"], row["operation"], row["variant"]): row for row in raw["counts"]["records"]}
report["cases"] = []
work_fields = ["storage_edit_callbacks", "storage_invalidated_units", "storage_changed_units", "glyph_callbacks", "glyphs_visited", "composed_queries", "explicit_buffer_allocations", "explicit_buffer_bytes", "typesetter_creates", "snapshot_characters", "cluster_suggestions", "line_creates", "token_advances"]
for fixture, operation in dict.fromkeys((row["fixture"], row["operation"]) for row in raw["counts"]["records"]):
    case = {"fixture": fixture, "operation": operation}
    for variant in ("base", "candidate"):
        rows = [row for row in raw["timing"]["records"] if row["fixture"] == fixture and row["operation"] == operation and row["variant"] == variant]
        measured = counts[fixture, operation, variant]
        case["characters"] = measured["characters"]
        case[variant] = {"wall_ms": [round(row["wall_ms"], 6) for row in rows], "delegate_ms": [round(row["delegate_ms"], 6) for row in rows], "counts": {key: measured[key] for key in work_fields}}
        case[variant]["median_wall_ms"] = statistics.median(case[variant]["wall_ms"][1:])
        case[variant]["median_delegate_ms"] = statistics.median(case[variant]["delegate_ms"][1:])
    case["added_wall_ms"] = case["candidate"]["median_wall_ms"] - case["base"]["median_wall_ms"]
    case["added_delegate_ms"] = case["candidate"]["median_delegate_ms"] - case["base"]["median_delegate_ms"]
    comparable = [field for field in work_fields if field not in ("composed_queries", "explicit_buffer_allocations", "explicit_buffer_bytes")]
    case["invalidation_and_typesetter_counts_equal"] = all(case["base"]["counts"][key] == case["candidate"]["counts"][key] for key in comparable)
    report["cases"].append(case)
    print(f"{fixture} {operation}: {case['base']['median_wall_ms']:.3f} -> {case['candidate']['median_wall_ms']:.3f} ms; added {case['added_wall_ms']:.3f} ms", flush=True)
(HERE / "results.json").write_text(json.dumps(report, indent=2) + "\n")
assert sum(path.stat().st_size for path in HERE.iterdir() if path.is_file()) < 150 * 1024
print("PASS: four bounded large-note cases; source and layout restored after start/end edit pairs; final evidence under 150 KiB")
