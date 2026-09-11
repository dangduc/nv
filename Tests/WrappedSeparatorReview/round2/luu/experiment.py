#!/usr/bin/env python3
"""Unshipped printable-ASCII shortcut: one 256K case and composed controls."""
from pathlib import Path
import json
import statistics
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
# Load only the frozen-source/scaffolding definitions, not the main benchmark.
scope = {"__file__": str(HERE / "run.py")}
exec((HERE / "run.py").read_text().split("report = {")[0], scope)
current = scope["delegate"](scope["HEAD"])
query = "[source rangeOfComposedCharacterSequenceAtIndex:index].length == 1"
ascii_guard = "(([source characterAtIndex:index-1] >= 0x21 && [source characterAtIndex:index-1] <= 0x7e && [source characterAtIndex:index+1] >= 0x21 && [source characterAtIndex:index+1] <= 0x7e) || " + query + ")"
assert current.count(query) == 1
experiment = current.replace(query, ascii_guard)
support = scope["support"]
for token, implementation in (("@BASE_DELEGATE@", current), ("@CANDIDATE_DELEGATE@", experiment)):
    support = support.replace(token, implementation.replace("[source rangeOfComposedCharacterSequenceAtIndex:index]", "CountComposed(source, index)"))
support = support.replace("@TYPESETTER@", scope["typesetter"])
with tempfile.TemporaryDirectory(prefix="experiment-", dir=HERE) as temporary:
    temp = Path(temporary)
    (temp / "support.m").write_text(support)
    (temp / "NVSourceTypesetter.h").write_text(scope["source"](scope["HEAD"], "Sources/Editor/NVSourceTypesetter.h"))
    binary = temp / "experiment"
    build = subprocess.run(["xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13", "-O2", "-fno-objc-arc", "-fblocks", "-DCOUNTS=1", "-Wno-deprecated-declarations", "-I", str(temp), "-framework", "Cocoa", "-framework", "CoreText", str(HERE / "experiment.m"), "-o", str(binary)], capture_output=True, text=True, timeout=30)
    build.check_returncode()
    output = temp / "output.json"
    run = subprocess.run([str(binary), str(output)], capture_output=True, text=True, timeout=30)
    (HERE / "experiment.log").write_text(build.stdout + build.stderr + run.stdout + run.stderr)
    print(run.stdout + run.stderr, end="")
    run.check_returncode()
    report = json.loads(output.read_text())
report["head"] = scope["HEAD"]
report["status"] = "experimental probe only; not shipped"
report["instrumented_timing"] = True
report["ascii_guard"] = "Both neighbors must be U+0021 through U+007E; all other cases retain the composed query."
for operation in ("initial", "start"):
    report.setdefault("summary", {})[operation] = {}
    for variant in ("current", "ascii-experiment"):
        rows = [row for row in report["records"] if row["operation"] == operation and row["variant"] == variant and row["trial"] > 0]
        report["summary"][operation][variant] = {key: statistics.median(row[key] for row in rows) for key in ("wall_ms", "delegate_ms", "composed_queries")}
(HERE / "experiment-results.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report["summary"], indent=2))
