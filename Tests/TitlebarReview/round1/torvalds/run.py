#!/usr/bin/env python3
"""Run the real copied-app menu, saved-layout, validation, and focus probe."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

repo = Path(__file__).resolve().parents[4]
here = Path(__file__).resolve().parent
out = repo / 'build/TitlebarReview/round1/torvalds'
out.mkdir(parents=True, exist_ok=True)
app = repo / 'build/DerivedData/Build/Products/Development/nvALT.app'
if not app.is_dir() or not (app / 'Contents/Info.plist').is_file():
    raise SystemExit('Build the Development app before running this copied-app probe.')
command = [sys.executable, str(repo / 'Tests/ViewControlsReview/run-probe.py'),
           '--probe', str(here / 'checks.inc'), '--timeout', '120']
result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
(out / 'run.log').write_text(result.stdout)
paths = ['Sources/Browser/AppController.h', 'Sources/Browser/AppController.m',
         'Sources/Browser/AppController_BrowserUI.m', 'Sources/Application/NVApplicationController.m']
record = {
    'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
    'command': command, 'exit_code': result.returncode,
    'pass_count': result.stdout.count('PASS:'),
    'passed': result.returncode == 0 and 'TORVALDS_REVIEW_PASS' in result.stdout,
    'source_sha256': {p: hashlib.sha256((repo / p).read_bytes()).hexdigest() for p in paths},
    'probe_sha256': hashlib.sha256((here / 'checks.inc').read_bytes()).hexdigest(),
    'limitations': ['Runs the actual Intel app on macOS 26.5.2, not macOS 10.13.',
                    'Export, Copy Note Link, and Delete verify live menu receivers and validation without executing external effects.',
                    'Uses isolated preferences and disposable notes; GUI access is serialized by the shared runner.'],
}
(out / 'results.json').write_text(json.dumps(record, indent=2) + '\n')
print(result.stdout)
if not record['passed']:
    raise SystemExit(result.returncode or 1)
