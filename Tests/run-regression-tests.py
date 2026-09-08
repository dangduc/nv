#!/usr/bin/env python3
"""Run desktop regression checks."""
from pathlib import Path
import subprocess
import sys

repo = Path(__file__).resolve().parents[1]
checks = [
    'source-highlighting/run.py',
    'source-storage/run.py',
    'source-viewers/run.py',
    'source-viewers/run-viewer.py',
    'source-workflow/run.py',
    'native-dependencies/run.py',
    'native-ui/run.py',
    'native-controls/run.py',
    'native-rendering/run.py',
    'ownership/run.py',
    'preview-lifetime/run.py',
    'search/run.py',
    'editing/run-probes.py',
    'selections/run-probes.py',
    'snapshot-diff/run.py',
    'fonts/run-probes.py',
    'columns/run-probes.py',
    'restoration/run-canaries.py',
]
for check in checks:
    print('Running ' + check, flush=True)
    subprocess.run([sys.executable, str(repo / 'Tests/Regression' / check)],
                   cwd=repo, check=True)
print('ALL REGRESSION CHECKS PASSED', flush=True)
