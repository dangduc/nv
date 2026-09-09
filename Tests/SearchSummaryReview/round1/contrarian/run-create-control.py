#!/usr/bin/env python3
"""Classify zero-result creation using the exact pre-change affordance in the same app."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

repo = Path(__file__).resolve().parents[4]
output = repo / 'build/SearchSummaryReview/round1/contrarian'
output.mkdir(parents=True, exist_ok=True)
old = subprocess.check_output(['git', 'show', '4624b3d:Sources/Browser/AppController_BrowserUI.m'], cwd=repo, text=True)
method = old[old.index('- (void)updateSearchAffordance {'):old.index('\n- (IBAction)newNote:', old.index('- (void)updateSearchAffordance {'))]
method = method.replace('- (void)updateSearchAffordance {', '- (void)nv_oldSummaryAffordance {', 1)
probe = output / 'create-control-generated.inc'
probe.write_text(method + '\n' + Path(__file__).with_name('create-control.inc').read_text())
inputs = [repo / 'Sources/Browser/AppController_BrowserUI.m',
          repo / 'build/DerivedData/Build/Products/Development/nvALT.app/Contents/MacOS/nvALT']

def hashes():
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}

before = hashes()
results = []
for variant in ['production', 'old-affordance']:
    env = dict(os.environ)
    env.pop('NV_SUMMARY_OLD_AFFORDANCE', None)
    if variant == 'old-affordance':
        env['NV_SUMMARY_OLD_AFFORDANCE'] = '1'
    result = subprocess.run([sys.executable, str(repo / 'Tests/ViewControlsReview/run-probe.py'),
                             '--probe', str(probe), '--timeout', '60'], cwd=repo, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (output / ('create-' + variant + '.log')).write_text(result.stdout)
    expected = result.returncode == 0 and 'CREATE_CONTROL_PASS' in result.stdout
    observations = [line.split('CREATE_CONTROL ', 1)[1] for line in result.stdout.splitlines() if 'CREATE_CONTROL oldMethod=' in line]
    results.append({'variant': variant, 'exit_code': result.returncode,
                    'checks_passed': result.stdout.count('PASS:'), 'expected': expected, 'observations': observations})
    print(json.dumps(results[-1]), flush=True)
after = hashes()
(output / 'create-control-results.json').write_text(json.dumps({'results': results, 'sha256_before': before,
    'sha256_after': after, 'inputs_unchanged': before == after,
    'renamed_old_method_sha256': hashlib.sha256(method.encode()).hexdigest()}, indent=2) + '\n')
raise SystemExit(0 if all(result['expected'] for result in results) and before == after else 1)
