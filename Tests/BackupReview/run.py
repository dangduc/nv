#!/usr/bin/env python3
"""Run current native review regressions with isolated logs, without the Intel app."""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--round", type=int, choices=(1, 2, 3), help="Run only this review round.")
args = parser.parse_args()
rounds = [HERE / f"round{args.round}"] if args.round else sorted(HERE.glob("round[123]"))
probes = [probe for directory in rounds for probe in sorted(directory.glob("*/run*.py"))]
if not probes:
    parser.error("No review probes exist for the selected round.")

output = ROOT / "build/BackupReview/validation"
output.mkdir(parents=True, exist_ok=True)
failures = []
for probe in probes:
    name = "-".join(probe.relative_to(HERE).with_suffix("").parts)
    log = output / f"{name}.log"
    with log.open("w") as stream:
        process = subprocess.Popen([sys.executable, str(probe)], cwd=ROOT,
                                   stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            passed = process.wait(timeout=180) == 0
        except subprocess.TimeoutExpired:
            passed = False
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            stream.write("\nReview runner exceeded its 180-second limit.\n")
    print(f"{'PASS' if passed else 'FAIL'} {probe.relative_to(ROOT)}", flush=True)
    if not passed:
        failures.append(probe)
        print(f"  Log: {log}", flush=True)

print(f"{len(probes) - len(failures)}/{len(probes)} native review runners passed.")
raise SystemExit(bool(failures))
