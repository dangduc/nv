#!/usr/bin/env python3
"""Benchmark production browser sessions with in-memory model doubles."""
from pathlib import Path
import sys
import subprocess
import tempfile

here = Path(__file__).resolve().parent
repo = here.parents[3]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags

with tempfile.TemporaryDirectory(prefix="nv-review-search-") as temporary:
    binary = Path(temporary) / "search-scaling"
    legacy = subprocess.check_output(["git", "show", "4c6cf45:NotationController.m"], cwd=repo, text=True)
    method = legacy[legacy.index("- (BOOL)filterNotesFromUTF8String:"):legacy.index("- (NSUInteger)preferredSelectedNoteIndex")]
    (Path(temporary) / "legacy-controller-search.inc").write_text(method)
    note = subprocess.check_output(["git", "show", "4c6cf45:NoteObject.m"], cwd=repo, text=True)
    functions = note[note.index("force_inline void resetFoundPtrsForNote"):note.index("BOOL noteTitleIsAPrefixOfOtherNoteTitle")]
    (Path(temporary) / "legacy-note-search.inc").write_text(functions)
    subprocess.run(["xcrun", "clang", "-O2", "-fno-objc-arc", "-Wno-deprecated-declarations",
        "-Wno-incomplete-implementation", "-Wno-protocol", "-Wno-incompatible-pointer-types", "-I", temporary,
        *include_flags(repo), "-include", str(repo / "Config/Notation_Prefix.pch"),
        "-framework", "Cocoa", "-framework", "Carbon", str(here / "search_scaling.m"),
        str(repo / "Sources/Browser/NVBrowserSession.m"), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=60)
