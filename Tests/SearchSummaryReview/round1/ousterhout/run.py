#!/usr/bin/env python3
"""Run the exact affordance method with native controls and immutable session states."""
import fcntl
import hashlib
import json
from pathlib import Path
import subprocess

repo = Path(__file__).resolve().parents[4]
here = Path(__file__).resolve().parent
out = repo / "build/SearchSummaryReview/round1/ousterhout"
out.mkdir(parents=True, exist_ok=True)
path = repo / "Sources/Browser/AppController_BrowserUI.m"
header = repo / "Sources/Browser/AppController.h"
def digest(value):
    return hashlib.sha256(value).hexdigest()
def extract(source):
    method = source[source.index("- (void)updateSearchAffordance {"):]
    return method[:method.index("\n}\n") + 3]
source = path.read_bytes()
production = extract(source.decode())
base = subprocess.check_output(["git", "show", "4624b3d:Sources/Browser/AppController_BrowserUI.m"], cwd=repo)
old = extract(base.decode())
assert production != old, "Wait for the production checkpoint before running this probe"
record = {"head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
          "source_before": {str(p.relative_to(repo)): digest(p.read_bytes()) for p in (path, header)},
          "base_source_sha256": digest(base), "runs": []}
lock_path = repo / "build/pr-review/gui.lock"
lock_path.parent.mkdir(parents=True, exist_ok=True)
for name, method in [("production", production), ("old-summary-control", old)]:
    directory = out / name
    directory.mkdir(exist_ok=True)
    (directory / "production.inc").write_text(method)
    binary = directory / "SummaryProbe"
    command = ["xcrun", "clang", "-arch", "arm64", "-fno-objc-arc", "-Wno-deprecated-declarations",
               "-framework", "Cocoa", "-I", str(directory), "-o", str(binary), str(here / "probe.m")]
    with (directory / "compile.log").open("w") as log:
        subprocess.run(command, cwd=repo, stdout=log, stderr=subprocess.STDOUT, check=True)
    with lock_path.open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        result = subprocess.run([str(binary)], cwd=repo, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=20)
    (directory / "run.log").write_text(result.stdout)
    expected = (result.returncode == 0 and "RESULT passes=" in result.stdout) if name == "production" else (
        result.returncode != 0 and "FAIL completed search hides the summary control" in result.stdout)
    entry = {"name": name, "exit_code": result.returncode, "pass_count": result.stdout.count("PASS "),
             "expected_outcome": expected, "method_sha256": digest(method.encode())}
    record["runs"].append(entry)
    print(json.dumps(entry), flush=True)
record["source_after"] = {str(p.relative_to(repo)): digest(p.read_bytes()) for p in (path, header)}
record["sources_unchanged"] = record["source_before"] == record["source_after"]
record["probe_hashes"] = {p.name: digest(p.read_bytes()) for p in (here / "probe.m", here / "run.py")}
(out / "results.json").write_text(json.dumps(record, indent=2) + "\n")
if not record["sources_unchanged"] or not all(x["expected_outcome"] for x in record["runs"]):
    raise SystemExit(1)
