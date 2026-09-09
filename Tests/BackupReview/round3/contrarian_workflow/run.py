#!/usr/bin/env python3
"""Run native pane-switch checks with extracted owner methods and the complete pane."""
from pathlib import Path
import argparse
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--negative-mutations", action="store_true")
args = parser.parse_args()
owner = (ROOT / "Sources/Preferences/PrefsWindowController.m").read_text()
switch_start = owner.index("- (void)switchViews:")
switch_end = owner.index("//elasticwork", switch_start)
switch = owner[switch_start:switch_end]
close_start = owner.index("- (BOOL)windowShouldClose:")
close_end = owner.index("- (void)windowDidResignMain:", close_start)
close = owner[close_start:close_end]
pane = ROOT / "Sources/Preferences/NVBackupPreferencesViewController.m"

with tempfile.TemporaryDirectory(prefix="nv-r3-workflow-") as temporary:
    directory = Path(temporary)
    (directory / "switch-owner.inc").write_text(switch)
    (directory / "close-owner.inc").write_text(close)
    binary = directory / "pane-switch"

    def run(source, capture=False):
        subprocess.run(["xcrun", "clang", "-fno-objc-arc", "-Werror", "-Wno-incomplete-implementation",
            "-Wno-deprecated-declarations", "-mmacosx-version-min=10.13", "-I", "Sources/Application", "-I", "Sources/Storage",
            "-I", "Sources/Preferences", "-I", temporary, str(HERE / "probe.m"), str(source),
            "-framework", "Cocoa", "-o", str(binary)], cwd=ROOT, check=True, timeout=30)
        return subprocess.run([str(binary)], cwd=ROOT, check=not capture, capture_output=capture, text=True, timeout=30)

    run(pane)
    if args.negative_mutations:
        mutations = {
            "hidden-status-refresh": ("    if (![self isViewLoaded]) return;", "    if (![self isViewLoaded] || ![[self view] window]) return;"),
            "discard-operation-error": ("    if (pendingFieldError) status = [status stringByAppendingFormat:@\"\\n%@ %@\",",
                "    if (pendingFieldError) status = [@\"\" stringByAppendingFormat:@\"\\n%@ %@\","),
        }
        original = pane.read_text()
        for name, (before, after) in mutations.items():
            assert original.count(before) == 1, (name, "mutation target moved")
            mutated = directory / f"{name}.m"
            mutated.write_text(original.replace(before, after, 1))
            result = run(mutated, capture=True)
            assert result.returncode != 0, (name, "unsafe mutation unexpectedly passed")
            print("REJECTED:", name, next(line for line in result.stderr.splitlines() if "FAIL:" in line), flush=True)
