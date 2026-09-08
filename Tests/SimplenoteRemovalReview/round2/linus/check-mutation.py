#!/usr/bin/env python3
"""Require the independent native probe to detect an omitted ODB callback."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[4]
review = Path(__file__).resolve().parent
result = subprocess.run([
    sys.executable, str(root / 'Tests/ViewControlsReview/run-probe.py'),
    '--probe', str(review / 'checks.inc'), '--prefix', str(review / 'prefix.h'),
    '--app', str(root / 'build/SimplenoteRemovalReview/round1.app'),
], env=dict(os.environ, NV_REVIEW_DROP_ODB_UPDATE='1'),
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
print(result.stdout, end='')
assert result.returncode == 1, 'Callback mutation must fail.'
assert 'FAIL: external update commits the exact source in the note model' in result.stdout
print('PASS: omitted ODB callback fails the intended exact-model-source assertion.')
