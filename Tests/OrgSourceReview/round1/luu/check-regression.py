#!/usr/bin/env python3
"""Check that the maintained regression rejects the original production loop."""
from pathlib import Path
import subprocess
import sys

here = Path(__file__).resolve().parent
repo = here.parents[3]
out = repo / 'build/OrgSourceReview/round1/luu/regression-before'
out.mkdir(parents=True, exist_ok=True)
runner = (repo / 'Tests/OrgSource/Links/run.py').read_text()
runner = runner.replace('repo = Path(__file__).resolve().parents[3]', f'repo = Path({str(repo)!r})')
runner = runner.replace("out = repo / 'build/OrgSource/Links'", f'out = Path({str(out)!r})')
runner = runner.replace("source = (repo / 'Sources/Editor/AttributedPlainText.m').read_text()",
    "source = subprocess.check_output(['git', 'show', 'decc6788e1a746b5425f3cd248cd93071c98b8b2:Sources/Editor/AttributedPlainText.m'], cwd=repo, text=True)")
runner = runner.replace("(Path(__file__).parent / 'probe.m').read_text()", "(repo / 'Tests/OrgSource/Links/probe.m').read_text()")
path = out / 'run.py'
path.write_text(runner)
result = subprocess.run([sys.executable, str(path)], capture_output=True, text=True)
output = f'exit_code={result.returncode}\n' + result.stdout + result.stderr
(here / 'regression-before.txt').write_text(output)
print(output)
assert result.returncode == 1
assert 'FAIL dense Org paragraph performs bounded line-boundary work' in output
print('PASS: the maintained regression rejects the original repeated line scans')
