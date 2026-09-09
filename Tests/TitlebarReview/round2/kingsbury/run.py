#!/usr/bin/env python3
"""Run locked copied-app asynchronous histories and a transient-intent control."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

repo = Path(__file__).resolve().parents[4]
here = Path(__file__).resolve().parent
out = repo / 'build/TitlebarReview/round2/kingsbury'
out.mkdir(parents=True, exist_ok=True)
paths = ['Sources/Browser/AppController.h', 'Sources/Browser/AppController.m',
         'Sources/Browser/AppController_BrowserUI.m', 'Sources/Browser/AppController_Search.m',
         'Sources/Browser/AppController_MultipleWindows.m', 'Sources/Browser/NVBrowserSession.m',
         'Sources/Search/NVSearchService.m', 'Sources/Search/NVSearchCorpus.m', 'Sources/Search/NVSearchQuery.m']
binary = repo / 'build/DerivedData/Build/Products/Development/nvALT.app/Contents/MacOS/nvALT'
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
before = {p: digest(repo / p) for p in paths}
baseline = '6b8d67514f4fc5bc2e9fca22816a32f30f59fb1c'
baseline_matches = all(hashlib.sha256(subprocess.check_output(['git','show',baseline+':'+p],cwd=repo)).hexdigest()==h for p,h in before.items())
binary_before = digest(binary)
command = [sys.executable, str(repo / 'Tests/ViewControlsReview/run-probe.py'), '--probe', str(here / 'checks.inc'),
           '--prefix', str(here / 'prefix.h'), '--timeout', '120']
records=[]
for name, extra in [('history',{}), ('retained-transient',{'NV_TITLEBAR_RETAIN_TRANSIENT':'1'})]:
    result=subprocess.run(command,env=dict(os.environ,**extra),text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (out/(name+'.log')).write_text(result.stdout)
    expected=(result.returncode==0 and 'TITLEBAR_ROUND2_KINGSBURY_PASS' in result.stdout) if name=='history' else (
        result.returncode!=0 and 'FAIL: native toolbar detachment cancels transient search intents' in result.stdout)
    record={'name':name,'command':command,'environment_overrides':extra,'exit_code':result.returncode,
            'expected_outcome':expected,'pass_count':result.stdout.count('PASS:')}
    records.append(record); print(json.dumps(record),flush=True)
after={p:digest(repo/p) for p in paths}
summary={'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),
         'production_baseline':baseline,'inputs_match_baseline':baseline_matches,
         'before_sha256':before,'after_sha256':after,'production_inputs_stable':before==after,
         'binary_before_sha256':binary_before,'binary_after_sha256':digest(binary),
         'fixture_sha256':{p.name:digest(p) for p in [here/'checks.inc',here/'prefix.h',Path(__file__)]},'runs':records}
(here/'results.json').write_text(json.dumps(summary,indent=2)+'\n')
if not all(r['expected_outcome'] for r in records) or before!=after or binary_before!=digest(binary) or not baseline_matches:
    raise SystemExit(1)
