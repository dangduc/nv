#!/usr/bin/env python3
"""Bounded headless checks of production browser dirty-row scheduling."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

suite = Path(__file__).resolve().parent
repo = suite.parents[3]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags

parser = argparse.ArgumentParser()
parser.add_argument("--baseline-reveal", action="store_true")
args = parser.parse_args()
variant = "baseline" if args.baseline_reveal else "candidate"
out = repo / "build/TypingReview/round1/kingsbury" / variant
out.mkdir(parents=True, exist_ok=True)
controller = (repo / "Sources/Browser/AppController.m").read_text()
start = controller.index("- (NSUInteger)revealNote:(NoteObject*)note options:(NSUInteger)opts {")
(out / "reveal.inc").write_text(controller[start:controller.index("\n}\n", start) + 3])
flags = ["-g", "-O1", "-arch", "x86_64", "-DUTF8PROC_STATIC",
         "-I" + str(out), "-I" + str(repo / "ThirdParty/fzf-native"), *include_flags(repo)]
session_source = "Sources/Browser/NVBrowserSession.m"
if args.baseline_reveal:
    flags += ["-DBASELINE_REVEAL"]
    session_source = str(out / "NVBrowserSession-baseline.m")
    Path(session_source).write_text(subprocess.check_output(["git", "show", "8dde5e8:Sources/Browser/NVBrowserSession.m"], cwd=repo, text=True))
sources = ["Sources/Search/NVFZF.c", "ThirdParty/fzf-native/fzf.c",
           "ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c",
           "Sources/Search/NVSearchQuery.m", "Sources/Search/NVSearchCorpus.m",
           "Sources/Search/NVSearchService.m", session_source,
           str(suite / "probe.m")]
commands, objects, compile_logs = [], [], []
for index, source in enumerate(sources):
    obj = out / f"{index}.o"
    language = ["-fblocks", "-fno-objc-arc", "-Wno-deprecated-declarations",
                "-Wno-incomplete-implementation", "-Wno-protocol", "-include",
                str(repo / "Config/Notation_Prefix.pch")] if source.endswith(".m") else ["-std=c11"]
    command = ["xcrun", "clang", *flags, *language, "-c", str(repo / source), "-o", str(obj)]
    commands.append(command)
    result = subprocess.run(command, capture_output=True, text=True, timeout=60)
    compile_logs.append(result.stdout + result.stderr)
    if result.returncode:
        (out / "compile.log").write_text("".join(compile_logs))
        raise SystemExit(result.stderr)
    objects.append(str(obj))
command = ["xcrun", "clang", *flags, *objects, "-framework", "Cocoa", "-framework", "Carbon", "-o", str(out / "probe")]
commands.append(command)
result = subprocess.run(command, capture_output=True, text=True, timeout=30)
compile_logs.append(result.stdout + result.stderr)
(out / "compile.log").write_text("".join(compile_logs))
if result.returncode:
    raise SystemExit(result.stderr)
result = subprocess.run([str(out / "probe")], capture_output=True, text=True, timeout=30)
(suite / f"{variant}-output.txt").write_text(result.stdout + result.stderr)
report = {"head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
          "command": "python3 Tests/TypingReview/round1/kingsbury/run.py" + (" --baseline-reveal" if args.baseline_reveal else ""), "compile_commands": commands,
          "native_exit": result.returncode, "passed": result.returncode == 0 and "PASS: browser interleavings" in result.stdout}
(suite / f"{variant}-results.json").write_text(json.dumps(report, indent=2) + "\n")
print(result.stdout, end="")
print(result.stderr, end="")
raise SystemExit(0 if report["passed"] else 1)
