#!/usr/bin/env python3
"""Compile production search sessions with a new deterministic mutation trace."""
from pathlib import Path
import sys
import subprocess
import tempfile

here = Path(__file__).resolve().parent
repo = here.parents[3]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags

with tempfile.TemporaryDirectory(prefix="nv-round2-luu-") as temporary:
    binary = Path(temporary) / "differential"
    subprocess.run(["xcrun", "clang", "-O2", "-fno-objc-arc", "-Wno-deprecated-declarations",
        "-Wno-incomplete-implementation", "-Wno-protocol", *include_flags(repo), "-include", str(repo / "Config/Notation_Prefix.pch"),
        "-framework", "Cocoa", "-framework", "Carbon", str(here / "differential.m"), str(repo / "Sources/Browser/NVBrowserSession.m"),
        "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=45)
