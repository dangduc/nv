#!/usr/bin/env python3
"""Exercise production controls in a disposable, serialized Intel app copy."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

repo = Path(__file__).resolve().parents[4]
output = repo / 'build/TitlebarReview/round1/contrarian'
output.mkdir(parents=True, exist_ok=True)
paths = ['Sources/Browser/AppController_BrowserUI.m', 'Sources/Browser/AppController.m',
         'Sources/Browser/AppController_Search.m', 'Sources/UI/DualField.m',
         'build/DerivedData/Build/Products/Development/nvALT.app/Contents/MacOS/nvALT',
         'Tests/TitlebarReview/round1/contrarian/checks.inc']
reviewed = '6b8d67514f4fc5bc2e9fca22816a32f30f59fb1c'
identity = {'reviewed_commit': reviewed,
            'checkout_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
            'sha256': {path: hashlib.sha256((repo / path).read_bytes()).hexdigest() for path in paths}}
identity['production_matches_reviewed_commit'] = all(
    (repo / path).read_bytes() == subprocess.check_output(['git', 'show', reviewed + ':' + path], cwd=repo)
    for path in paths if path.startswith('Sources/'))
if not identity['production_matches_reviewed_commit']:
    raise SystemExit('Production sources changed since the reviewed commit; use a matching build and review target.')
(output / 'identity.json').write_text(json.dumps(identity, indent=2) + '\n')
results = []
for variant in ['production', 'empty-semantic-title-control']:
    env = dict(os.environ)
    env.pop('NV_CONTRARIAN_NEGATIVE', None)
    if variant != 'production':
        env['NV_CONTRARIAN_NEGATIVE'] = '1'
    command = [sys.executable, str(repo / 'Tests/ViewControlsReview/run-probe.py'),
               '--probe', str(Path(__file__).with_name('checks.inc')), '--timeout', '60']
    result = subprocess.run(command, cwd=repo, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (output / (variant + '.log')).write_text(result.stdout)
    passes = result.stdout.count('PASS:')
    expected = (result.returncode == 0 and 'CONTRARIAN_REVIEW_PASS' in result.stdout) if variant == 'production' else (
        result.returncode == 1 and 'FAIL: visually hidden title retains the selected note identity for accessibility' in result.stdout)
    results.append({'variant': variant, 'exit_code': result.returncode, 'checks_passed': passes, 'expected': expected})
    print(json.dumps(results[-1]), flush=True)
    if variant == 'production' and not expected:
        print(result.stdout[-10000:])
        break
(output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
raise SystemExit(0 if len(results) == 2 and all(result['expected'] for result in results) else 1)
