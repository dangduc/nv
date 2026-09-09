#!/usr/bin/env python3
"""Run isolated, locked copied-app histories and a query-clobber negative control."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

repo = Path(__file__).resolve().parents[4]
here = Path(__file__).resolve().parent
out = repo / 'build/TitlebarReview/round1/kingsbury'
out.mkdir(parents=True, exist_ok=True)
command = [sys.executable, str(repo / 'Tests/ViewControlsReview/run-probe.py'),
           '--probe', str(here / 'checks.inc'), '--timeout', '120']
records = []
for name, launches, extra in [('history', 2, {}), ('query-clobber', 1, {'NV_TITLEBAR_QUERY_CLOBBER': '1'})]:
    result = subprocess.run(command + ['--launches', str(launches)], env=dict(os.environ, **extra),
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (out / (name + '.log')).write_text(result.stdout)
    expected = ((result.returncode == 0 and 'KINGSBURY_PHASE_2_PASS' in result.stdout) if name == 'history'
                else (result.returncode != 0 and 'FAIL: visible query matches the independent history model' in result.stdout))
    record = {'name': name, 'exit_code': result.returncode, 'expected_outcome': expected,
              'pass_count': result.stdout.count('PASS:'), 'command': command + ['--launches', str(launches)]}
    records.append(record)
    print(json.dumps(record), flush=True)
paths = ['Sources/Browser/AppController.h', 'Sources/Browser/AppController.m',
         'Sources/Browser/AppController_BrowserUI.m', 'Sources/Browser/AppController_MultipleWindows.m']
summary = {'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
           'source_sha256': {p: hashlib.sha256((repo / p).read_bytes()).hexdigest() for p in paths},
           'probe_sha256': hashlib.sha256((here / 'checks.inc').read_bytes()).hexdigest(), 'runs': records}
(out / 'results.json').write_text(json.dumps(summary, indent=2) + '\n')
if not all(r['expected_outcome'] for r in records):
    raise SystemExit(1)
