#!/usr/bin/env python3
"""Prove the gated histories detect publication without a generation fence."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[4]
production = (root / "Sources/Editor/NVSourceHighlighter.m").read_text()
guard = "!closed && generation == requestGeneration && [syntaxIdentifier isEqualToString:syntax]"
assert production.count(guard) == 1
mutant = production.replace(guard, "!closed && [syntaxIdentifier isEqualToString:syntax]")
with tempfile.TemporaryDirectory(prefix="nvalt-stale-review-") as temporary:
    implementation = Path(temporary) / "NVSourceHighlighter.m"
    implementation.write_text(mutant)
    result = subprocess.run([
        "python3", str(root / "Tests/SyntaxFlickerReview/run-parser-probe.py"),
        "--probe", str(Path(__file__).with_name("probe.m")),
        "--implementation", str(implementation),
    ], cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(result.stdout, end="")
    expected = "obsolete positive, nil, or empty outcome leaves provisional display untouched"
    if result.returncode == 0 or expected not in result.stdout:
        raise SystemExit("FAIL: generation-fence mutation did not trigger the expected assertion")
    print("PASS: removing only the generation fence fails the stale-positive history")
