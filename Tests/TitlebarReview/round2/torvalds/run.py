#!/usr/bin/env python3
"""Run isolated copied-app toolbar compatibility checks and a negative control."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys

repo = Path(__file__).resolve().parents[4]
here = Path(__file__).resolve().parent
out = repo / 'build/TitlebarReview/round2/torvalds'
out.mkdir(parents=True, exist_ok=True)
parser = argparse.ArgumentParser()
parser.add_argument('--negative', action='store_true')
args = parser.parse_args()
mode = 'negative' if args.negative else 'native'
app = repo / 'build/DerivedData/Build/Products/Development/nvALT.app'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
paths = ['Sources/Browser/AppController.h', 'Sources/Browser/AppController.m', 'Sources/Browser/AppController_BrowserUI.m',
         'Sources/UI/DualField.h', 'Sources/UI/DualField.m', 'Tests/ViewControlsReview/run-probe.py',
         'Tests/Regression/native-controls/probes.m', 'Tests/Regression/native-controls/checks.inc']
paths += [str((here / name).relative_to(repo)) for name in ('checks.inc', 'run.py')]
def hashes():
    return {path: hashlib.sha256((repo / path).read_bytes()).hexdigest() for path in paths}
before = hashes()
record = {'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
          'production_commit': '6b8d67514f4fc5bc2e9fca22816a32f30f59fb1c', 'mode': mode,
          'source_sha256_before': before, 'app_binary_sha256_before': hashlib.sha256(binary.read_bytes()).hexdigest(),
          'os': subprocess.check_output(['sw_vers'], text=True).strip(),
          'toolchain': subprocess.check_output(['xcodebuild', '-version'], text=True).strip()}
for path in paths[:3]:
    baseline = subprocess.check_output(['git', 'show', '6b8d675:' + path], cwd=repo)
    assert hashlib.sha256(baseline).hexdigest() == before[path], path + ' differs from the production checkpoint'
command = [sys.executable, str(repo / 'Tests/ViewControlsReview/run-probe.py'), '--probe', str(here / 'checks.inc'), '--timeout', '120']
print('Starting', mode, 'copied-app probe with the shared GUI lock.', flush=True)
environment = dict(os.environ)
if args.negative: environment['NV_TITLEBAR_R2_NO_REINSERT'] = '1'
result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=environment)
(out / (mode + '.log')).write_text(result.stdout)
record.update(command=command, exit_code=result.returncode, source_sha256_after=hashes(),
              app_binary_sha256_after=hashlib.sha256(binary.read_bytes()).hexdigest(), pass_count=result.stdout.count('PASS:'))
record['changed_inputs'] = [path for path, digest in before.items() if record['source_sha256_after'][path] != digest]
record['expected_result'] = (result.returncode == 1 and 'FAIL: Search recovers exactly one valid toolbar item' in result.stdout) if args.negative else (result.returncode == 0 and 'TORVALDS_R2_PASS' in result.stdout)
(out / (mode + '-results.json')).write_text(json.dumps(record, indent=2) + '\n')
print(result.stdout, end='')
assert not record['changed_inputs'], record['changed_inputs']
assert record['app_binary_sha256_before'] == record['app_binary_sha256_after'], 'The source app binary changed during execution.'
if not record['expected_result']: raise SystemExit(result.returncode or 1)
print('PASS:', mode, 'produced the expected result.')
