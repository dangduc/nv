#!/usr/bin/env python3
"""Count production browser preview reuse and deferred teardown lifetimes."""
from pathlib import Path
import sys
import argparse
import subprocess
import tempfile

here = Path(__file__).resolve().parent
repo = here.parents[3]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags

parser = argparse.ArgumentParser()
parser.add_argument("--canaries", action="store_true", help="Check that cache and ownership regressions fail the probe.")
arguments = parser.parse_args()
with tempfile.TemporaryDirectory(prefix="nv-round3-luu-") as temporary:
    binary = Path(temporary) / "cache-lifetime"
    source_text = (repo / "Sources/Browser/NVBrowserSession.m").read_text()
    cases = [("production", source_text, None)]
    if arguments.canaries:
        candidates = [
            ("disable-cache-hit", "[previewCache objectForKey:key]", "nil", "1280 preview requests build only 128 distinct window previews"),
            ("omit-resize-invalidation", "visibleFilteredRows:(NSRange)rows forceUpdate:(BOOL)force {\n    [previewCache removeAllObjects];",
             "visibleFilteredRows:(NSRange)rows forceUpdate:(BOOL)force {", "resize invalidation bounds the first preview cache"),
            ("omit-library-release", "[library release];", "", "the last deferred session releases its library and candidate notes"),
        ]
        for name, before, after, expected in candidates:
            assert before in source_text, "Canary anchor missing: " + name
            cases.append((name, source_text.replace(before, after, 1), expected))
    for name, text, expected in cases:
        source = Path(temporary) / (name + ".m")
        source.write_text(text)
        subprocess.run(["xcrun", "clang", "-O2", "-fno-objc-arc", "-Wno-deprecated-declarations",
            "-Wno-incomplete-implementation", "-Wno-protocol", "-Wno-objc-protocol-method-implementation",
            *include_flags(repo),
            "-include", str(repo / "Config/Notation_Prefix.pch"), "-framework", "Cocoa", "-framework", "Carbon",
            str(here / "cache_lifetime.m"), str(source), "-o", str(binary)], check=True)
        result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
        if expected:
            assert result.returncode == 1 and "FAIL: " + expected in result.stderr, name + result.stdout + result.stderr
            print("CANARY REJECTED: " + name + ": " + result.stderr.strip(), flush=True)
        else:
            print(result.stdout, end="", flush=True)
            assert result.returncode == 0, result.stderr
