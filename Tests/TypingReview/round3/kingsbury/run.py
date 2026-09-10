#!/usr/bin/env python3
"""Bounded headless checks of production browser dirty-row scheduling."""
import json
import os
import hashlib
from pathlib import Path
import subprocess
import sys

suite = Path(__file__).resolve().parent
repo = suite.parents[3]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags

out = repo / "build/TypingReview/round3/kingsbury"
out.mkdir(parents=True, exist_ok=True)
flags = ["-g", "-O1", "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-arch", "x86_64", "-DUTF8PROC_STATIC",
         "-I" + str(out), "-I" + str(repo / "ThirdParty/fzf-native"), *include_flags(repo)]
session_source = "Sources/Browser/NVBrowserSession.m"
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
result = subprocess.run([str(out / "probe")], capture_output=True, text=True, timeout=30, env=dict(os.environ, ASAN_OPTIONS="detect_leaks=0:halt_on_error=1", UBSAN_OPTIONS="halt_on_error=1"))
(suite / "output.txt").write_text(result.stdout + result.stderr)
(out / "output.txt").write_text(result.stdout + result.stderr)
report = {"head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
          "command": "python3 Tests/TypingReview/round3/kingsbury/run.py", "compile_commands": commands,
          "source_sha256": {source: hashlib.sha256((repo / source).read_bytes()).hexdigest() for source in sources},
          "sanitizers": ["address", "undefined"], "native_exit": result.returncode, "passed": result.returncode == 0 and "PASS: multi-browser projection matrix" in result.stdout}
(suite / "results.json").write_text(json.dumps(report, indent=2) + "\n")
(out / "results.json").write_text(json.dumps(report, indent=2) + "\n")
print(result.stdout, end="")
print(result.stderr, end="")
raise SystemExit(0 if report["passed"] else 1)
