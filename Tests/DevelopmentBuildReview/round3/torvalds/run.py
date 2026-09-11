#!/usr/bin/env python3
"""Check production backup-directory ownership with bounded disposable fixtures."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
REF = "47d18f43cadb1a2eeeed9c7fbe379795c76faae7"
OUT = REPO / "build/DevelopmentBuildReview/round3/torvalds"
OUT.mkdir(parents=True, exist_ok=True)
hashes = {}
for path in ["Sources/Storage/NVBackupStore.m", "Sources/Storage/NVBackupStore.h", "Sources/Storage/NVBackupController.m"]:
    content = (REPO / path).read_bytes()
    frozen = subprocess.check_output(["git", "show", f"{REF}:{path}"], cwd=REPO, timeout=15)
    assert content == frozen, path
    hashes[path] = hashlib.sha256(content).hexdigest()
summary = {"reviewedCommit": REF, "productionHashes": hashes,
           "macOS": subprocess.check_output(["sw_vers"], text=True), "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True), "runs": []}
for arch in ["arm64", "x86_64"]:
    binary = OUT / f"probe-{arch}"
    subprocess.run(["xcrun", "clang", "-arch", arch, f"-mmacosx-version-min={'11.0' if arch=='arm64' else '10.13'}",
                    "-fblocks", "-fno-objc-arc", "-Wall", "-Wextra", "-Werror", "-framework", "Foundation",
                    "-I", str(REPO / "Sources/Storage"), str(HERE / "probe.m"), "-o", str(binary)], check=True, timeout=45)
    with tempfile.TemporaryDirectory(prefix="nvalt-directory-review-") as temporary:
        result = OUT / f"results-{arch}.json"
        run = subprocess.run(["arch", f"-{arch}", str(binary), str(Path(temporary).resolve()), str(result)], capture_output=True, text=True, timeout=45)
        (OUT / f"output-{arch}.log").write_text(run.stdout + run.stderr)
        print(f"{arch}: {run.stdout}{run.stderr}", end="", flush=True)
        run.check_returncode()
        summary["runs"].append({"architecture": arch, **json.loads(result.read_text())})
summary["probeHashes"] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [HERE / "probe.m", HERE / "run.py"]}
(HERE / "results.json").write_text(json.dumps(summary, indent=2) + "\n")
