#!/usr/bin/env python3
"""Run native hidden-interface histories against every shipped localization."""
from pathlib import Path
import argparse
import subprocess
import sys

repo = Path(__file__).resolve().parents[4]
root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, default=repo / 'build/ViewControlsReview/round1/nvALT.app')
parser.add_argument('languages', nargs='*', default=['en', 'de', 'fr', 'it', 'pt-PT', 'zh'])
args = parser.parse_args()
for language in args.languages:
    command = [sys.executable, str(repo / 'Tests/ViewControlsReview/run-probe.py'),
        '--probe', str(root / 'checks.inc'), '--app', str(args.app),
        '--launch-arg=-AppleLanguages', '--launch-arg=(' + language + ')']
    with (root / ('output-' + language + '.txt')).open('w') as output:
        result = subprocess.run(command, cwd=repo, stdout=output, stderr=subprocess.STDOUT)
    print(language, 'exit', result.returncode, flush=True)
    if result.returncode:
        raise SystemExit(result.returncode)
