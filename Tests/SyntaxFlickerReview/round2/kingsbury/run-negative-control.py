#!/usr/bin/env python3
"""Prove automatic histories detect loss of rescheduling after stale work."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[4]
production = (root / "Sources/Editor/NVSourceHighlighter.m").read_text()
reschedule = "} else if (!closed) [self schedule];"
assert production.count(reschedule) == 1
mutant = production.replace(reschedule, "}")
with tempfile.TemporaryDirectory(prefix="nvalt-scheduling-review-") as temporary:
    implementation = Path(temporary) / "NVSourceHighlighter.m"
    implementation.write_text(mutant)
    result = subprocess.run([
        "python3", str(root / "Tests/SyntaxFlickerReview/run-parser-probe.py"),
        "--probe", str(Path(__file__).with_name("probe.m")),
        "--implementation", str(implementation),
    ], cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(result.stdout, end="")
    expected = "latest captures become current in every layout within three seconds"
    if result.returncode == 0 or expected not in result.stdout:
        raise SystemExit("FAIL: removing stale-completion rescheduling did not trigger the expected assertion")
    print("PASS: removing only stale-completion rescheduling fails automatic eventual completion")
