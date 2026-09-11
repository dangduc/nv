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
    'org-preview/run.py',
    'org-preview-ui/run.py',
    'source-viewers/run.py',
    'source-viewers/run-viewer.py',
    'source-workflow/run.py',
    'native-dependencies/run.py',
    'native-ui/run.py',
    'native-controls/run.py',
    'native-rendering/run.py',
    'user-schemes/run.py',
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
    'SourceAnalysis/run.py', 'TypingRefresh/run.py', 'SourceBackspace/run.py', 'SourceEditing/run.py', 'ListRedraw/run.py',
    'OrgSource/run.py', 'OrgSource/Links/run.py', 'OrgSource/Integration/run.py',
    'FuzzySearch/Core/run.py', 'FuzzySearch/run-service-tests.py', 'FuzzySearch/Browser/run.py',
    'FuzzySearch/Persistence/run.py', 'FuzzySearch/Highlights/run.py', 'FuzzySearch/HighlightBounds/run.py', 'FuzzySearch/Lifecycle/run.py', 'FuzzySearch/PositionMapping/run.py', 'FuzzySearch/UI/run.py',
    'BackupStore/run.py', 'BackupStore/run-teardown.py',
    'BackupCoordinator/run.py', 'BackupPreferences/run.py', 'BackupArchive/native/run.py', 'BackupArchive/run.py',
]] + [repo / 'Tests/Regression' / check for check in checks]
for path in paths:
    print('Running ' + str(path.relative_to(repo)), flush=True)
    subprocess.run([sys.executable, str(path)],
                   cwd=repo, check=True)
print('ALL REGRESSION CHECKS PASSED', flush=True)
