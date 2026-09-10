#!/usr/bin/env python3
"""Compare matching production typing benchmark reports."""
import argparse
import json
from pathlib import Path
import statistics

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("baseline", type=Path)
parser.add_argument("candidate", type=Path)
args = parser.parse_args()


def grouped(path):
    groups = {}
    for row in json.loads(path.read_text()):
        groups.setdefault(row["case"], []).append(row)
    return groups


before, after = grouped(args.baseline), grouped(args.candidate)
if set(before) != set(after):
    raise SystemExit("Reports have different cases.")
print("| Case | Keys per trial | Baseline CPU ms | Candidate CPU ms | CPU reduction | Baseline key mean ms | Candidate key mean ms |")
print("| --- | ---: | ---: | ---: | ---: | ---: | ---: |")
for case, old in before.items():
    new = after[case]
    if len(old) != len(new) or {r["keys"] for r in old + new} != {old[0]["keys"]}:
        raise SystemExit(f"Incompatible trials: {case}")
    median = lambda rows, key: statistics.median(r[key] for r in rows)
    old_cpu, new_cpu = median(old, "cpu_ms"), median(new, "cpu_ms")
    print(f"| {case} | {old[0]['keys']} | {old_cpu:.1f} | {new_cpu:.1f} | {(1-new_cpu/old_cpu)*100:.1f}% | "
          f"{median(old, 'key_mean_ms'):.3f} | {median(new, 'key_mean_ms'):.3f} |")
