#!/usr/bin/env python3
"""Identical common-action focus observations in independently copied apps."""
from pathlib import Path
import argparse
import subprocess
import sys

root = Path(__file__).resolve().parent
repo = root.parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--label', required=True)
parser.add_argument('languages', nargs='*', default=['en', 'zh'])
args = parser.parse_args()
for language in args.languages:
    command = [sys.executable, str(repo / 'Tests/ViewControlsReview/run-probe.py'),
        '--probe', str(root / 'focus-control.inc'), '--app', str(args.app),
        '--launch-arg=-AppleLanguages', '--launch-arg=(' + language + ')']
    print('RUN', ' '.join(command), flush=True)
    with (root / ('control-' + args.label + '-' + language + '.txt')).open('w') as output:
        result = subprocess.run(command, cwd=repo, stdout=output, stderr=subprocess.STDOUT)
    print(args.label, language, 'exit', result.returncode, flush=True)
    if result.returncode:
        raise SystemExit(result.returncode)
