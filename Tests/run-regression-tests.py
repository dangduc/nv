#!/usr/bin/env python3
"""Run desktop regression checks."""
from pathlib import Path
import subprocess
import sys

repo = Path(__file__).resolve().parents[1]
checks = [
    'native-list/run-native.py',
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
paths = [repo / 'Tests' / check for check in [
    'BackupStore/run.py', 'BackupStore/run-teardown.py',
    'BackupCoordinator/run.py', 'BackupPreferences/run.py', 'BackupArchive/native/run.py', 'BackupArchive/run.py',
]] + [repo / 'Tests/Regression' / check for check in checks]
for path in paths:
    print('Running ' + str(path.relative_to(repo)), flush=True)
    subprocess.run([sys.executable, str(path)],
                   cwd=repo, check=True)
print('ALL REGRESSION CHECKS PASSED', flush=True)
