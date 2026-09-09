#!/usr/bin/env python3
"""Native descriptor-lifetime checks against the production backup store."""
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
with tempfile.TemporaryDirectory(prefix="nv-review-torvalds-r1-") as temporary:
    temporary = Path(temporary).resolve()
    executable = temporary / "probe"
    subprocess.run([
        "xcrun", "clang", "-fblocks", "-fno-objc-arc", "-Wall", "-Wextra", "-Werror",
        "-mmacosx-version-min=10.13", "-DNVBACKUPSTORE_TESTING", "-framework", "Foundation",
        "-I", str(ROOT / "Sources/Storage"), str(ROOT / "Sources/Storage/NVBackupStore.m"),
        str(HERE / "main.m"), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable), str(temporary / "fixtures")], check=True, timeout=60)
