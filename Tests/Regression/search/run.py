#!/usr/bin/env python3
"""Exercise production browser search against deterministic in-memory fixtures."""
import argparse
from pathlib import Path
import subprocess
import tempfile

here = Path(__file__).resolve().parent
repo = here.parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--source-ref", help="Compile a historical NVBrowserSession.m to check regression sensitivity.")
arguments = parser.parse_args()
with tempfile.TemporaryDirectory(prefix="nv-search-regression-") as temporary:
    binary = Path(temporary) / "search-regression"
    source = repo / "NVBrowserSession.m"
    if arguments.source_ref:
        source = Path(temporary) / "NVBrowserSession.m"
        source.write_bytes(subprocess.check_output(["git", "show", arguments.source_ref + ":NVBrowserSession.m"], cwd=repo))
    subprocess.run(["xcrun", "clang", "-O2", "-fno-objc-arc", "-Wno-deprecated-declarations",
        "-Wno-incomplete-implementation", "-Wno-protocol", "-I", str(repo), "-I", str(repo / "RBSplitView"),
        "-I", str(repo / "PTHotKeys"), "-I", str(repo / "ODBEditor"), "-include", str(repo / "Notation_Prefix.pch"),
        "-framework", "Cocoa", "-framework", "Carbon", str(here / "search_regression.m"), str(source),
        "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
