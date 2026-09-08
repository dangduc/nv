#!/usr/bin/env python3
"""Run the same native edit-history probe against the PR base and fix."""
from pathlib import Path
import subprocess
import sys

here = Path(__file__).resolve().parent
root = here.parents[3]
build = root / "build/SyntaxFlickerReview/round2/dan_luu"
build.mkdir(parents=True, exist_ok=True)
runner = root / "Tests/SyntaxFlickerReview/run-parser-probe.py"
for label, revision in (
    ("base", "8cd2c9591041b8cdef367c6a0f78304e00192a45"),
    ("head", "65e1608ff4e9977ec2d7a09297739152f9cfc935"),
):
    implementation = build / f"{label}-highlighter.m"
    implementation.write_bytes(subprocess.check_output(
        ["git", "show", f"{revision}:Sources/Editor/NVSourceHighlighter.m"], cwd=root
    ))
    # Keep comparisons sequential: both variants use the same runner output path.
    # Write fresh output under build/ so committed observations remain unchanged.
    output = build / f"{label}-comparison-output.txt"
    with output.open("w") as log:
        log.write(f"revision={revision}\n")
        log.flush()
        subprocess.run(
            [sys.executable, str(runner), "--probe", str(here / "probe.m"),
             "--implementation", str(implementation)],
            cwd=root, stdout=log, stderr=subprocess.STDOUT, check=True,
        )
    print(f"PASS {label}: {output}")
