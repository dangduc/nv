#!/usr/bin/env python3
"""Review evidence: actual coordinator, deterministic mocked store/clock/queues."""
from pathlib import Path
import argparse
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[4]
parser = argparse.ArgumentParser()
parser.add_argument("--baseline", action="store_true", help="Reproduce the original retention defect from 30c3cf8")
args = parser.parse_args()
includes = []
for directory in sorted({p.parent for p in (ROOT / "Sources").rglob("*.h")}):
    includes.extend(["-I", str(directory)])
with tempfile.TemporaryDirectory(prefix="nv-review-ousterhout-") as temp:
    binary = str(Path(temp) / "retention-contract")
    source = ROOT / "Sources/Storage/NVBackupController.m"
    if args.baseline:
        for filename in ("NVBackupController.h", "NVBackupController.m"):
            (Path(temp) / filename).write_bytes(subprocess.check_output(["git", "show", "30c3cf816c80e4ff957223d55f22b36074880ef1:Sources/Storage/" + filename], cwd=ROOT))
        source = Path(temp) / "NVBackupController.m"
    subprocess.run(["xcrun", "clang", "-fno-objc-arc", "-fblocks", "-Wno-incomplete-implementation",
        "-mmacosx-version-min=10.13", *([] if args.baseline else ["-DEXPECT_FIXED"]), *includes,
        str(Path(__file__).with_name("retention-contract.m")),
        str(source), "-framework", "Cocoa", "-framework", "CoreServices", "-o", binary], check=True)
    subprocess.run([binary, temp], check=True, timeout=30)
