#!/usr/bin/env python3
"""Exercise real PreviewController capture completion with controlled WebKit reply order."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[4]
sdk = Path(subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip())
with tempfile.TemporaryDirectory(prefix="nvalt-capture-order-") as temp:
    binary = Path(temp) / "capture-order"
    subprocess.run([
        "xcrun", "clang", "-fno-objc-arc", "-fblocks", "-Wno-deprecated-declarations",
        "-framework", "Cocoa", "-framework", "WebKit", "-lxml2",
        "-I", str(sdk / "usr/include/libxml2"), "-I", str(repo / "Sources/Preview"),
        str(repo / "Sources/Preview/NVNoteContentSnapshot.m"),
        str(repo / "Sources/Preview/NVMarkupRenderer.m"),
        str(repo / "Sources/Preview/PreviewController.m"),
        str(Path(__file__).with_name("capture-order.m")), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True, timeout=10)
