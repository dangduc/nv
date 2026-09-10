#!/usr/bin/env python3
"""Compile real source analysis and control result delivery for lifecycle tests."""
from pathlib import Path
import hashlib
import json
import platform
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BUILD = ROOT / "build/org-source-review/round1/kingsbury"
BUILD.mkdir(parents=True, exist_ok=True)
VENDOR = ROOT / "ThirdParty/TreeSitter"
COMMON = ["xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13", "-std=c11", "-O2", "-fblocks"]
production = ROOT / "Sources/Editor/NVSourceHighlighter.m"
inputs = {
    "production_sha256": production,
    "org_parser_sha256": VENDOR / "org/src/parser.c",
    "org_scanner_sha256": VENDOR / "org/src/scanner.c",
    "org_query_sha256": ROOT / "Resources/Syntax/org.scm",
}
before = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in inputs.items()}
head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
objects = []
for source in sorted((ROOT / "Sources/Editor/TreeSitter").glob("NVTreeSitter*.c")):
    obj = BUILD / (source.stem + ".o")
    subprocess.run(COMMON + ["-I", str(VENDOR / "runtime/include"), "-I", str(VENDOR / "runtime/src"), "-I", str(VENDOR / "org/src"), "-c", str(source), "-o", str(obj)], check=True)
    objects.append(str(obj))
binary = BUILD / "probe"
subprocess.run(COMMON + ["-I", str(ROOT / "Sources/Editor"), "-framework", "Cocoa", str(production), str(HERE / "probe.m")] + objects + ["-o", str(binary)], check=True)
result = subprocess.run([str(binary), str(ROOT / "Resources/Syntax")], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
(HERE / "output.txt").write_text(result.stdout)
metadata = {
    "head_before_build": head,
    **before,
    "inputs_unchanged_during_run": before == {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in inputs.items()},
    "host": platform.platform(),
    "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
    "exit_code": result.returncode,
}
(HERE / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
print(result.stdout, end="")
if not metadata["inputs_unchanged_during_run"]:
    raise SystemExit("Production inputs changed during this run; repeat after those edits finish.")
sys.exit(result.returncode)
