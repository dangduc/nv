#!/usr/bin/env python3
"""Compile and exercise the production backup store with disposable files."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="nvalt-backup-store-") as temporary:
    temporary = Path(temporary).resolve()
    executable = temporary / "backup-store-tests"
    subprocess.run([
        "xcrun", "clang", "-fblocks", "-fno-objc-arc", "-Wall", "-Wextra", "-Werror",
        "-mmacosx-version-min=10.13", "-DNVBACKUPSTORE_TESTING", "-framework", "Foundation",
        "-I", str(ROOT / "Sources/Storage"), str(ROOT / "Sources/Storage/NVBackupStore.m"),
        str(ROOT / "Tests/BackupStore/main.m"), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable), str(temporary / "fixtures")], check=True, timeout=180)
