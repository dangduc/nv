#!/usr/bin/env python3
"""Bounded coordinator workflow checks; all collaborators and limits are in REPORT.md."""
from pathlib import Path
import argparse
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--expect-context-isolation", action="store_true")
parser.add_argument("--context-mutation", action="store_true")
parser.add_argument("--regress-context", action="store_true", help="Restore the combined stale-context/error branch in a temporary source copy; the regression must fail.")
args = parser.parse_args()
includes = []
for directory in sorted({path.parent for path in (ROOT / "Sources").rglob("*.h")}):
    includes.extend(["-I", str(directory)])
with tempfile.TemporaryDirectory(prefix="nv-r2-workflow-") as temporary:
    production = ROOT / "Sources/Storage/NVBackupController.m"
    if args.context_mutation or args.regress_context:
        source = production.read_text()
        before = "            if (!restored || context != contextGeneration) {"
        after = ("            if (stopped || context != contextGeneration) { busy = NO; [self changed]; return; }\n"
            "            if (!restored) {")
        if args.regress_context:
            assert source.count(after) == 1
            source = source.replace(after, before, 1)
        elif before in source:
            assert source.count(before) == 1
            source = source.replace(before, after, 1)
        else:
            assert source.count(after) == 1
        production = Path(temporary) / "context-mutation.m"
        production.write_text(source)
    binary = Path(temporary) / "restore-flow"
    subprocess.run(["xcrun", "clang", "-fno-objc-arc", "-fblocks", "-Wno-incomplete-implementation",
        "-mmacosx-version-min=10.13", *includes, str(HERE / "restore-flow.m"), str(production),
        "-framework", "Cocoa", "-framework", "CoreServices", "-o", str(binary)], cwd=ROOT, check=True)
    subprocess.run([str(binary), temporary, "--expect-context-isolation"],
        cwd=ROOT, check=True, timeout=30)
