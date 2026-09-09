#!/usr/bin/env python3
"""Review evidence: actual coordinator, deterministic mocked store/clock/queues."""
from pathlib import Path
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[4]
includes = []
for directory in sorted({p.parent for p in (ROOT / "Sources").rglob("*.h")}):
    includes.extend(["-I", str(directory)])
with tempfile.TemporaryDirectory(prefix="nv-review-ousterhout-") as temp:
    binary = str(Path(temp) / "retention-contract")
    subprocess.run(["xcrun", "clang", "-fno-objc-arc", "-fblocks", "-Wno-incomplete-implementation",
        "-mmacosx-version-min=10.13", *includes,
        str(Path(__file__).with_name("retention-contract.m")),
        str(ROOT / "Sources/Storage/NVBackupController.m"), "-framework", "Cocoa", "-framework", "CoreServices", "-o", binary], check=True)
    subprocess.run([binary, temp], check=True, timeout=30)
