#!/usr/bin/env python3
"""Exercise nested native browser scopes with the current and forced fallback paths."""
from pathlib import Path
import subprocess
import tempfile

here = Path(__file__).resolve().parent
root = here.parents[3]
source = (root / "Sources/Browser/AppController_BrowserUI.m").read_text()
start = source.index("- (void)browserAppearanceChanged {")
method = source[start:source.index("\n}", start) + 2]
modern = "if (@available(macOS 11.0, *)) [[window effectiveAppearance] performAsCurrentDrawingAppearance:update];"
if method.count(modern) != 1:
    raise SystemExit("FAIL: expected the corrected production availability branch")
# This replaces only the unavailable-path choice. The fallback body is copied
# from production and runs against the actual AppController and native views.
forced = method.replace("- (void)browserAppearanceChanged {", "- (void)nv_ouFallbackAppearanceChanged {")
forced = forced.replace(modern, "if (NO) { }")
with tempfile.TemporaryDirectory(prefix="nvalt-ousterhout-r2-") as directory:
    probe = Path(directory) / "probe.inc"
    probe.write_text(forced + "\n" + (here / "probe.inc").read_text())
    subprocess.run(["python3", str(root / "Tests/ViewControlsReview/run-probe.py"),
        "--probe", str(probe), "--prefix", str(here / "prefix.h")], check=True)
