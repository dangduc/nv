#!/usr/bin/env python3
"""Compile the unmodified editing session with an in-memory note double."""
from pathlib import Path
import subprocess
import tempfile

here = Path(__file__).resolve().parent
repo = here.parents[3]
with tempfile.TemporaryDirectory(prefix="nv-review-memory-") as temporary:
    binary = Path(temporary) / "undo-memory"
    subprocess.run(["xcrun", "clang", "-O2", "-fno-objc-arc", "-Wno-deprecated-declarations",
        "-I", str(repo), "-I", str(repo / "RBSplitView"), "-I", str(repo / "PTHotKeys"),
        "-I", str(repo / "ODBEditor"), "-include", str(repo / "Notation_Prefix.pch"),
        "-framework", "Cocoa", "-framework", "Carbon", str(here / "undo_memory.m"),
        str(repo / "NVNoteEditingSession.m"), "-o", str(binary)], check=True)
    for length, edits in [(10240, 200), (102400, 200), (1048576, 200), (1048576, 400)]:
        subprocess.run([str(binary), str(length), str(edits)], check=True, timeout=60)
