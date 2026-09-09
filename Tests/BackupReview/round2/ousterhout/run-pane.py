#!/usr/bin/env python3
"""Check pane lifetime boundaries with native field editors and a fake coordinator."""
from pathlib import Path
import subprocess
import tempfile
import argparse

ROOT = Path(__file__).resolve().parents[4]
parser = argparse.ArgumentParser()
parser.add_argument("--expect-fixed", action="store_true")
parser.add_argument("--close-mutation", action="store_true", help="End the field editor in the extracted close delegate.")
args = parser.parse_args()
source = (ROOT / "Sources/Preferences/PrefsWindowController.m").read_text()
start = source.index("- (void)windowWillClose:")
end = source.index("- (void)windowDidResignMain:", start)
close_method = source[start:end]
if args.close_mutation:
    close_method = close_method.replace("{", "{\n    [window makeFirstResponder:nil];", 1)
with tempfile.TemporaryDirectory(prefix="nv-review-r2-pane-") as temporary:
    (Path(temporary) / "close-owner.inc").write_text(close_method)
    binary = Path(temporary) / "pane-lifetime"
    command = ["xcrun", "clang", "-fno-objc-arc", "-Wno-incomplete-implementation",
        "-mmacosx-version-min=10.13", "-I", "Sources/Application", "-I", "Sources/Storage",
        "-I", "Sources/Preferences", "-I", temporary, str(Path(__file__).with_name("pane-lifetime.m")),
        "Sources/Preferences/NVBackupPreferencesViewController.m", "-framework", "Cocoa", "-o", str(binary)]
    subprocess.run(command, cwd=ROOT, check=True)
    subprocess.run([str(binary), *(["--expect-fixed"] if args.expect_fixed else [])], cwd=ROOT, check=True, timeout=30)
