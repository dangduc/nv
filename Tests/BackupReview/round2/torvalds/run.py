#!/usr/bin/env python3
"""Native maintenance and deletion checks with disposable backup fixtures."""
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
with tempfile.TemporaryDirectory(prefix="nv-review-torvalds-r2-") as temporary:
    temporary = Path(temporary).resolve()
    executable = temporary / "probe"
    subprocess.run([
        "xcrun", "clang", "-fblocks", "-fno-objc-arc", "-Wall", "-Wextra", "-Werror",
        "-mmacosx-version-min=10.13", "-DNVBACKUPSTORE_TESTING", "-framework", "Foundation",
        "-I", str(ROOT / "Sources/Storage"), str(ROOT / "Sources/Storage/NVBackupStore.m"),
        str(HERE / "main.m"), "-o", str(executable),
    ], check=True, timeout=60)
    subprocess.run([str(executable), str(temporary / "fixtures")], check=True, timeout=60)
