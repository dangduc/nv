#!/usr/bin/env python3
"""Measure sustained dirty-row deadlines and metadata bursts in production methods."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

suite = Path(__file__).resolve().parent
repo = suite.parents[3]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags

out = repo / "build/TypingReview/round3/luu"
out.mkdir(parents=True, exist_ok=True)
controller = (repo / "Sources/Application/NVApplicationController.m").read_text()
def method(prefix):
    start = controller.index(prefix)
    opening = controller.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (controller[end] == "{") - (controller[end] == "}")
        end += 1
    return controller[start:end] + "\n"
prefixes = ["- (NSArray *)browserControllers", "- (NVSearchNoteSnapshot *)searchSnapshotForNote:",
            "- (void)invalidateBrowserSearches", "- (void)searchableNoteDidChange:",
            "- (void)refreshBrowsers", "- (void)scheduleBrowserRefresh", "- (void)rowShouldUpdate:",
            "- (void)noteMetadataUpdated:", "- (void)titleUpdatedForNote:", "- (void)noteEditorChanged:"]
(out / "coordinator.inc").write_text("\n".join(method(p) for p in prefixes))
flags = ["-g", "-O1", "-arch", "x86_64", "-DUTF8PROC_STATIC",
         "-I" + str(out), "-I" + str(repo / "ThirdParty/fzf-native"), *include_flags(repo)]
sources = ["Sources/Search/NVFZF.c", "ThirdParty/fzf-native/fzf.c",
           "ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c", "Sources/Search/NVSearchQuery.m",
           "Sources/Search/NVSearchCorpus.m", "Sources/Search/NVSearchService.m",
           "Sources/Browser/NVBrowserSession.m", str(suite / "probe.m")]
objects, compile_logs = [], []
for index, source in enumerate(sources):
    obj = out / f"{index}.o"
    language = ["-fblocks", "-fno-objc-arc", "-Wno-deprecated-declarations",
                "-Wno-incomplete-implementation", "-Wno-protocol", "-include",
                str(repo / "Config/Notation_Prefix.pch")] if source.endswith(".m") else ["-std=c11"]
    command = ["xcrun", "clang", *flags, *language, "-c", str(repo / source), "-o", str(obj)]
    result = subprocess.run(command, capture_output=True, text=True, timeout=60)
    compile_logs.append(result.stdout + result.stderr)
    if result.returncode:
        (out / "compile.log").write_text("".join(compile_logs))
        raise SystemExit(result.stderr)
    objects.append(str(obj))
command = ["xcrun", "clang", *flags, *objects, "-framework", "Cocoa", "-framework", "Carbon", "-o", str(out / "probe")]
result = subprocess.run(command, capture_output=True, text=True, timeout=30)
compile_logs.append(result.stdout + result.stderr)
(out / "compile.log").write_text("".join(compile_logs))
if result.returncode:
    raise SystemExit(result.stderr)
result = subprocess.run([str(out / "probe")], capture_output=True, text=True, timeout=30)
(suite / "output.txt").write_text(result.stdout + result.stderr)
report = {"head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
          "command": "python3 Tests/TypingReview/round3/luu/run.py",
          "controller_sha256": hashlib.sha256(controller.encode()).hexdigest(),
          "browser_source_sha256": hashlib.sha256((repo / "Sources/Browser/NVBrowserSession.m").read_bytes()).hexdigest(),
          "macos": subprocess.check_output(["sw_vers", "-productVersion"], text=True).strip(),
          "compiler": subprocess.check_output(["xcrun", "clang", "--version"], text=True).splitlines()[0],
          "native_exit": result.returncode, "passed": result.returncode == 0 and "PASS: sustained coordinator scheduling" in result.stdout}
report["checks"] = result.stdout.count("PASS: ") - 1
report["metrics"] = []
for line in result.stdout.splitlines():
    if line.startswith("METRIC "):
        fields = line.split()
        item = {"scenario": fields[1]}
        for field in fields[2:]:
            key, value = field.split("=", 1)
            item[key] = float(value) if key.endswith("_ms") else int(value)
        report["metrics"].append(item)
(suite / "results.json").write_text(json.dumps(report, indent=2) + "\n")
print(result.stdout, end="")
print(result.stderr, end="")
raise SystemExit(0 if report["passed"] else 1)
