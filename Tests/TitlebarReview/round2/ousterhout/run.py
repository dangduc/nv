#!/usr/bin/env python3
"""Observe toolbar editing transitions and normal secondary-window teardown."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

repo = Path(__file__).resolve().parents[4]
here = Path(__file__).resolve().parent
out = repo / "build/TitlebarReview/round2/ousterhout"
out.mkdir(parents=True, exist_ok=True)
paths = ["Sources/Browser/AppController.h", "Sources/Browser/AppController.m",
         "Sources/Browser/AppController_BrowserUI.m", "Sources/Browser/AppController_MultipleWindows.m",
         "Sources/Application/NVApplicationController.m", "Sources/UI/DualField.m"]
def hashes():
    return {p: hashlib.sha256((repo / p).read_bytes()).hexdigest() for p in paths}

record = {"head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
          "source_before": hashes(), "runs": []}
command = [sys.executable, str(repo / "Tests/ViewControlsReview/run-probe.py"),
           "--probe", str(here / "checks.inc"), "--prefix", str(here / "instrumentation.h"), "--timeout", "90"]
for name, extra in [("production", {}), ("retaining-cycle-control", {"NV_OWNERSHIP_CYCLE_CONTROL": "1"})]:
    result = subprocess.run(command, cwd=repo, env=dict(os.environ, **extra),
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (out / (name + ".log")).write_text(result.stdout)
    expected = (result.returncode == 0 and "OUSTERHOUT_ROUND_2_PASS" in result.stdout) if name == "production" else (
        result.returncode != 0 and "FAIL: native close releases the secondary controller without manual toolbar detachment" in result.stdout)
    entry = {"name": name, "exit_code": result.returncode, "pass_count": result.stdout.count("PASS:"),
             "expected_outcome": expected, "command": command}
    record["runs"].append(entry)
    print(json.dumps(entry), flush=True)
record["source_after"] = hashes()
record["sources_unchanged"] = record["source_before"] == record["source_after"]
record["probe_hashes"] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in (here / "checks.inc", here / "instrumentation.h", here / "run.py")}
(out / "results.json").write_text(json.dumps(record, indent=2) + "\n")
if not record["sources_unchanged"] or not all(run["expected_outcome"] for run in record["runs"]):
    raise SystemExit(1)
