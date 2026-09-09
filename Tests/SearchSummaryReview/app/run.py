#!/usr/bin/env python3
"""Check the completed search UI in an isolated copy of the Development app."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[3]
raise SystemExit(subprocess.call([
    sys.executable, str(root / 'Tests/ViewControlsReview/run-probe.py'),
    '--probe', str(Path(__file__).with_name('checks.inc')), '--timeout', '90',
], cwd=root))
