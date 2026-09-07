#!/usr/bin/env python3
"""Run acceptance checks added for multiwindow review findings."""
from pathlib import Path
import subprocess
import sys

repo = Path(__file__).resolve().parents[1]
checks = [
    'ownership/run.py',
    'search/run.py',
    'editing/run-probes.py',
    'fonts/run-probes.py',
    'columns/run-probes.py',
    'restoration/run-canaries.py',
]
for check in checks:
    print('Running ' + check, flush=True)
    subprocess.run([sys.executable, str(repo / 'Tests/Regression' / check)],
                   cwd=repo, check=True)
print('ALL MULTIWINDOW REGRESSION CHECKS PASSED', flush=True)
