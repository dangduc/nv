#!/usr/bin/env python3
"""Exercise production browser search against deterministic in-memory fixtures."""
import argparse
from pathlib import Path
import sys
import subprocess
import tempfile

here = Path(__file__).resolve().parent
repo = here.parents[2]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags

parser = argparse.ArgumentParser()
parser.add_argument("--source-ref", help="Compile a historical NVBrowserSession.m to check regression sensitivity.")
arguments = parser.parse_args()
with tempfile.TemporaryDirectory(prefix="nv-search-regression-") as temporary:
    binary = Path(temporary) / "search-regression"
    source = repo / "Sources/Browser/NVBrowserSession.m"
    if arguments.source_ref:
        source = Path(temporary) / "NVBrowserSession.m"
        paths = subprocess.check_output([
            "git", "ls-tree", "-r", "--name-only", arguments.source_ref, "--",
            "Sources/Browser/NVBrowserSession.m", "NVBrowserSession.m",
        ], cwd=repo, text=True).splitlines()
        if len(paths) != 1:
            raise SystemExit("Expected one NVBrowserSession.m at the requested source ref.")
        source.write_bytes(subprocess.check_output(["git", "show", arguments.source_ref + ":" + paths[0]], cwd=repo))
    subprocess.run(["xcrun", "clang", "-O2", "-fno-objc-arc", "-Wno-deprecated-declarations",
        "-Wno-incomplete-implementation", "-Wno-protocol", *include_flags(repo), "-include", str(repo / "Config/Notation_Prefix.pch"),
        "-framework", "Cocoa", "-framework", "Carbon", str(here / "search_regression.m"), str(source),
        "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
