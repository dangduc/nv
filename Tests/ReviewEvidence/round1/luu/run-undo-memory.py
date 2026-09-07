#!/usr/bin/env python3
"""Compile the unmodified editing session with an in-memory note double."""
from pathlib import Path
import sys
import subprocess
import tempfile

here = Path(__file__).resolve().parent
repo = here.parents[3]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags

with tempfile.TemporaryDirectory(prefix="nv-review-memory-") as temporary:
    binary = Path(temporary) / "undo-memory"
    subprocess.run(["xcrun", "clang", "-O2", "-fno-objc-arc", "-Wno-deprecated-declarations",
        *include_flags(repo), "-include", str(repo / "Config/Notation_Prefix.pch"),
        "-framework", "Cocoa", "-framework", "Carbon", str(here / "undo_memory.m"),
        str(repo / "Sources/Editor/NVNoteEditingSession.m"), "-o", str(binary)], check=True)
    for length, edits in [(10240, 200), (102400, 200), (1048576, 200), (1048576, 400)]:
        subprocess.run([str(binary), str(length), str(edits)], check=True, timeout=60)
