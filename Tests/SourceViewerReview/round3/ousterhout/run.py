#!/usr/bin/env python3
"""Compile production provider and test controlled callback histories without a GUI."""
from pathlib import Path
import subprocess
import tempfile
repo = Path(__file__).resolve().parents[4]
with tempfile.TemporaryDirectory(prefix="nv-round3-capture-") as root:
    binary = Path(root) / "capture-probe"
    sdk = Path(subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip())
    subprocess.run(["xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13", "-fno-objc-arc", "-fblocks",
        "-Wno-deprecated-declarations", "-framework", "Cocoa", "-framework", "WebKit", "-lxml2",
        "-I", str(sdk/"usr/include/libxml2"), "-I", str(repo/"Sources/Preview"),
        str(repo/"Sources/Preview/NVNoteContentSnapshot.m"), str(repo/"Sources/Preview/NVMarkupRenderer.m"),
        str(repo/"Sources/Preview/PreviewController.m"), str(Path(__file__).with_name("probe.m")), "-o", str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)], timeout=15).returncode)
