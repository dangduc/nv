#!/usr/bin/env python3
"""Exercise production capture and offline restore in a copied app and disposable library."""
from pathlib import Path
import subprocess
import sys
repo = Path(__file__).resolve().parents[2]
subprocess.run([sys.executable, str(repo / 'Tests/ViewControlsReview/run-probe.py'),
    '--probe', str(Path(__file__).with_name('checks.inc')),
    '--prefix', str(Path(__file__).with_name('prefix.m')), *sys.argv[1:]], check=True)
