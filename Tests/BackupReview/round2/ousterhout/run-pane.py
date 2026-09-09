#!/usr/bin/env python3
"""Check pane lifetime boundaries with native field editors and a fake coordinator."""
from pathlib import Path
import subprocess
import tempfile
import argparse

ROOT = Path(__file__).resolve().parents[4]
parser = argparse.ArgumentParser()
parser.add_argument("--expect-fixed", action="store_true", help="Compatibility option; corrected assertions are always active.")
parser.add_argument("--negative-mutations", action="store_true")
args = parser.parse_args()
source = (ROOT / "Sources/Preferences/PrefsWindowController.m").read_text()
start = source.index("- (BOOL)windowShouldClose:")
end = source.index("- (void)windowDidResignMain:", start)
close_method = source[start:end]
with tempfile.TemporaryDirectory(prefix="nv-review-r2-pane-") as temporary:
    (Path(temporary) / "close-owner.inc").write_text(close_method)
    binary = Path(temporary) / "pane-lifetime"
    command = ["xcrun", "clang", "-fno-objc-arc", "-Werror", "-Wno-incomplete-implementation",
        "-mmacosx-version-min=10.13", "-I", "Sources/Application", "-I", "Sources/Storage",
        "-I", "Sources/Preferences", "-I", temporary, str(Path(__file__).with_name("pane-lifetime.m")),
        "Sources/Preferences/NVBackupPreferencesViewController.m", "-framework", "Cocoa", "-o", str(binary)]
    subprocess.run(command, cwd=ROOT, check=True)
    subprocess.run([str(binary)], cwd=ROOT, check=True, timeout=30)
    if args.negative_mutations:
        changed = close_method.replace("- (BOOL)windowShouldClose:(id)sender {", "- (BOOL)windowShouldClose:(id)sender { return YES;", 1)
        assert changed != close_method
        (Path(temporary) / "close-owner.inc").write_text(changed)
        subprocess.run(command, cwd=ROOT, check=True)
        result = subprocess.run([str(binary)], cwd=ROOT, capture_output=True, text=True, timeout=30)
        assert result.returncode != 0, "skipping the close contract unexpectedly passed"
        print("REJECTED: skip-window-close-contract:", next(line for line in result.stderr.splitlines() if "FAIL:" in line))
