#!/usr/bin/env python3
"""Exercise an early return after the joined caller acquires its newer query."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[4]
original = Path(__file__).with_name("probe.m").read_text()
anchor = "    Reply(v,0,@420);\n    Check([[[v viewerState] objectForKey:@\"find\"] isEqual:@\"newer query\"],"
replacement = '''    Returns(v,3);
    Check([[[v viewerState] objectForKey:@"find"] isEqual:@"newer query"], @"return before reply adopts the latest joined caller's query");
    Reply(v,0,@420);
    Check([[[v viewerState] objectForKey:@"find"] isEqual:@"newer query"],'''
assert original.count(anchor) == 1
with tempfile.TemporaryDirectory(prefix="nv-round3-capture-return-") as root:
    root = Path(root)
    probe = root / "return-probe.m"
    probe.write_text(original.replace(anchor, replacement))
    sdk = Path(subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip())
    binary = root / "capture-probe"
    subprocess.run(["xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13", "-fno-objc-arc", "-fblocks",
        "-Wno-deprecated-declarations", "-framework", "Cocoa", "-framework", "WebKit", "-lxml2",
        "-I", str(sdk / "usr/include/libxml2"), "-I", str(repo / "Sources/Preview"),
        str(repo / "Sources/Preview/NVNoteContentSnapshot.m"), str(repo / "Sources/Preview/NVMarkupRenderer.m"),
        str(repo / "Sources/Preview/PreviewController.m"), str(probe), "-o", str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)], timeout=15).returncode)
