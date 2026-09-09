#!/usr/bin/env python3
"""Review search-summary removal through real app accessibility and native controls."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

repo = Path(__file__).resolve().parents[4]
output = repo / 'build/SearchSummaryReview/round1/contrarian'
output.mkdir(parents=True, exist_ok=True)
reviewed = '72c668cc5329ce6e48850377b35ec7d6d5b27d5b'
paths = ['Sources/Browser/AppController_BrowserUI.m', 'Sources/Browser/AppController_Search.m',
         'Sources/UI/NotesTableView.m', 'Sources/Browser/NVBrowserSession.m',
         'Tests/SearchSummaryReview/round1/contrarian/checks.inc',
         'build/DerivedData/Build/Products/Development/nvALT.app/Contents/MacOS/nvALT']

def hashes():
    return {path: hashlib.sha256((repo / path).read_bytes()).hexdigest() for path in paths}

identity = {'reviewed_production_commit': reviewed,
            'checkout_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
            'sha256_before': hashes()}
identity['production_matches_reviewed_commit'] = all(
    (repo / path).read_bytes() == subprocess.check_output(['git', 'show', reviewed + ':' + path], cwd=repo)
    for path in paths if path.startswith('Sources/'))
if not identity['production_matches_reviewed_commit']:
    raise SystemExit('Production inputs no longer match the reviewed commit.')
results = []
for variant in ['production', 'visible-summary', 'reserved-gap']:
    env = dict(os.environ)
    env.pop('NV_SUMMARY_CONTRARIAN_NEGATIVE', None)
    if variant != 'production':
        env['NV_SUMMARY_CONTRARIAN_NEGATIVE'] = variant
    command = [sys.executable, str(repo / 'Tests/ViewControlsReview/run-probe.py'),
               '--probe', str(Path(__file__).with_name('checks.inc')), '--timeout', '60']
    result = subprocess.run(command, cwd=repo, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (output / (variant + '.log')).write_text(result.stdout)
    failure = 'the removed summary has no residual element in the window accessibility tree' if variant == 'visible-summary' else (
        'normal search reserves no blank summary strip above the notes list')
    expected = result.returncode == 0 and 'SEARCH_SUMMARY_CONTRARIAN_PASS' in result.stdout if variant == 'production' else (
        result.returncode == 1 and ('FAIL: ' + failure) in result.stdout)
    results.append({'variant': variant, 'exit_code': result.returncode,
                    'checks_passed': result.stdout.count('PASS:'), 'expected': expected})
    print(json.dumps(results[-1]), flush=True)
    if variant == 'production' and not expected:
        print(result.stdout[-12000:])
        break
identity['sha256_after'] = hashes()
identity['inputs_unchanged'] = identity['sha256_before'] == identity['sha256_after']
(output / 'identity.json').write_text(json.dumps(identity, indent=2) + '\n')
(output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
raise SystemExit(0 if len(results) == 3 and all(result['expected'] for result in results) and identity['inputs_unchanged'] else 1)
