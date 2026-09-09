#!/usr/bin/env python3
"""Check both User Scheme palettes in a disposable native application."""
import argparse
import os
from pathlib import Path
import subprocess
import sys

here = Path(__file__).resolve().parent
repo = here.parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, default=repo / 'build/DerivedData/Build/Products/Development/nvALT.app')
parser.add_argument('--artifacts', type=Path, help='Write screenshots of the disposable windows and settings')
args = parser.parse_args()
subprocess.run([sys.executable, str(here / 'compatibility.py')], check=True)
environment = dict(os.environ)
if args.artifacts:
    args.artifacts.mkdir(parents=True, exist_ok=True)
    environment['NV_USER_SCHEMES_ARTIFACTS'] = str(args.artifacts.resolve())
for probe, prefix, launches in [('checks.inc', 'support.h', '2'),
                                ('dynamic-colors.inc', 'dynamic-colors.h', '1')]:
    result = subprocess.run([sys.executable, str(repo / 'Tests/ViewControlsReview/run-probe.py'),
        '--probe', str(here / probe), '--prefix', str(here / prefix),
        '--app', str(args.app), '--launches', launches], env=environment)
    if result.returncode:
        raise SystemExit(result.returncode)
