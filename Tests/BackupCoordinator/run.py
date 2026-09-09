#!/usr/bin/env python3
"""Test the production backup coordinator with a deterministic clock and queues."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "build" / "BackupCoordinator"
OUTPUT.mkdir(parents=True, exist_ok=True)
includes = []
for directory in sorted({path.parent for path in (ROOT / "Sources").rglob("*.h")}):
    includes.extend(["-I", str(directory)])
subprocess.run([
    "xcrun", "clang", "-fno-objc-arc", "-fblocks", "-Wno-incomplete-implementation",
    "-mmacosx-version-min=10.13", *includes,
    "Tests/BackupCoordinator/coordinator.m", "Sources/Storage/NVBackupController.m",
    "-framework", "Cocoa", "-framework", "CoreServices", "-o", str(OUTPUT / "coordinator"),
], cwd=ROOT, check=True)
with tempfile.TemporaryDirectory(prefix="nvalt-backup-coordinator-") as temporary:
    subprocess.run([str(OUTPUT / "coordinator"), temporary], cwd=ROOT, check=True, timeout=30)
