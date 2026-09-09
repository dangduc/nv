#!/usr/bin/env python3
"""Reproduce the scoped AppKit cell-focus comparison in PR and baseline app copies."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

repo = Path(__file__).resolve().parents[4]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline-app', type=Path,
                    default=repo / 'build/TitlebarBaseline/build/DerivedData/Build/Products/Development/nvALT.app')
args = parser.parse_args()
probe = Path(__file__).with_name('focus-control.inc')
output = repo / 'build/TitlebarReview/round2/contrarian'
output.mkdir(parents=True, exist_ok=True)
apps = {'head': repo / 'build/DerivedData/Build/Products/Development/nvALT.app', 'base': args.baseline_app}
paths = [probe, *(app / 'Contents/MacOS/nvALT' for app in apps.values())]

def hashes():
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}

before = hashes()
results = []
for label, app in apps.items():
    command = [sys.executable, str(repo / 'Tests/ViewControlsReview/run-probe.py'),
               '--probe', str(probe), '--app', str(app), '--timeout', '60']
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (output / ('focus-traversal-' + label + '.log')).write_text(result.stdout)
    expected = result.returncode == 0 and 'FOCUS_CONTROL_PASS checks=5' in result.stdout
    for field in ['production', 'stock']:
        for path in ['cell-old-api', 'cell-protocol-api']:
            expected = expected and f'label={field} path={path} fieldEditor=0' in result.stdout
        expected = expected and f'label={field} path=view-protocol-api fieldEditor=1' in result.stdout
    results.append({'app': label, 'exit_code': result.returncode, 'expected_matrix': expected})
    print(json.dumps(results[-1]), flush=True)
after = hashes()
(output / 'focus-control-results.json').write_text(json.dumps(
    {'results': results, 'sha256_before': before, 'sha256_after': after, 'inputs_unchanged': before == after}, indent=2) + '\n')
raise SystemExit(0 if all(result['expected_matrix'] for result in results) and before == after else 1)
