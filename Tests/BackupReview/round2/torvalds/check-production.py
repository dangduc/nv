#!/usr/bin/env python3
"""Strict compilation and static analysis of the two corrected production files."""
from pathlib import Path
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
includes = [flag for directory in sorted({path.parent for path in (ROOT / "Sources").rglob("*.h")})
            for flag in ("-I", str(directory))]
sources = [ROOT / "Sources/Storage/NVBackupStore.m", ROOT / "Sources/Storage/NVBackupController.m"]
common = ["xcrun", "clang", "-fblocks", "-fno-objc-arc", "-Wall", "-Wextra", "-Werror",
          "-Wno-unused-parameter", "-Wno-deprecated-declarations", "-mmacosx-version-min=10.13", *includes]
with tempfile.TemporaryDirectory(prefix="nv-r2-production-check-") as temporary:
    for architecture in ("arm64", "x86_64"):
        for source in sources:
            subprocess.run([*common, "-arch", architecture, "-fsyntax-only", str(source)], check=True, timeout=60)
            output = Path(temporary) / f"{source.stem}-{architecture}.plist"
            subprocess.run([*common, "-arch", architecture, "--analyze", "-Xanalyzer", "-analyzer-output=plist",
                            str(source), "-o", str(output)], check=True, timeout=60)
            diagnostics = plistlib.loads(output.read_bytes())["diagnostics"]
            assert not diagnostics, (architecture, source, diagnostics)
            print(f"PASS: {architecture} {source.name}: strict compile; static analysis diagnostics=0", flush=True)
