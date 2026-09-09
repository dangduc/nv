#!/usr/bin/env python3
"""Measure the copied Intel app and an independent width-cap negative control."""
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys

root = Path(__file__).resolve().parents[4]
here = Path(__file__).resolve().parent
out = root / 'build/TitlebarReview/round2/luu'
out.mkdir(parents=True, exist_ok=True)
paths = ['Sources/Browser/AppController_BrowserUI.m', 'Sources/Browser/AppController.m',
         'Sources/UI/DualField.m', 'build/DerivedData/Build/Products/Development/nvALT.app/Contents/MacOS/nvALT']

def hashes():
    return {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in paths}

record = {'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
          'macOS': subprocess.check_output(['sw_vers'], text=True), 'machine': platform.machine(),
          'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True),
          'before': hashes(), 'variants': {}}
(out / 'identity-before.json').write_text(json.dumps(record, indent=2) + '\n')
command = [sys.executable, str(root / 'Tests/ViewControlsReview/run-probe.py'), '--probe',
           str(here / 'checks.inc'), '--timeout', '120']
for variant in ['production', 'width_cap_negative_control']:
    env = dict(os.environ, NV_TITLEBAR_RESULT=str(out / 'result.json'))
    if variant != 'production':
        env['NV_TITLEBAR_CAP_WIDTH'] = '1'
    with (out / (variant + '.log')).open('w') as log:
        # The common runner acquires build/pr-review/gui.lock before copying or launching the app.
        result = subprocess.run(command, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT)
    record['variants'][variant] = {'returncode': result.returncode}
    if variant == 'production' and result.returncode:
        break
record['after'] = hashes()
record['unchanged'] = record['before'] == record['after']
if (out / 'result.json').exists() and record['variants']['production']['returncode'] == 0:
    data = json.loads((out / 'result.json').read_text())
    record['geometryRows'] = len(data['geometry'])
    record['resizes'] = len(data['timings'])
    record['sourceLength'] = data['sourceLength']
    for mode in ['source', 'preview']:
        values = sorted(row['resizeMilliseconds'] + row['explicitLayoutMilliseconds']
                        for row in data['timings'] if row['scenario'].startswith(mode))
        record[mode + 'SynchronousResizePlusLayoutMilliseconds'] = {
            'samples': len(values), 'median': statistics.median(values),
            'p95': values[int((len(values) - 1) * .95)], 'max': max(values)}
(out / 'summary.json').write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps(record, indent=2))
assert record['unchanged'], 'production source or binary changed during this run'
assert record['variants']['production']['returncode'] == 0, 'production probe failed'
assert record['variants']['width_cap_negative_control']['returncode'] != 0, 'negative control was not detected'
assert 'negative-control-max-width-325 settled: attached Search fills available toolbar width' in (
    out / 'width_cap_negative_control.log').read_text(), 'negative control did not reach its geometry assertion'
