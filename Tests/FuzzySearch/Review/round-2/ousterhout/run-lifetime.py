#!/usr/bin/env python3
"""Exercise cancelled production browser-session lifetime with a queued worker."""
import argparse, hashlib, json, os
from pathlib import Path
import subprocess, sys
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
sys.path.insert(0, str(ROOT / 'Tests'))
from compiler_support import include_flags
p = argparse.ArgumentParser()
p.add_argument('--sanitize', action='store_true')
p.add_argument('--repair-control', action='store_true')
a = p.parse_args()
variant = ('sanitize' if a.sanitize else 'native') + ('-repair-control' if a.repair_control else '')
out = ROOT / 'build/FuzzySearchReview/round-2/ousterhout' / variant
out.mkdir(parents=True, exist_ok=True)
fixture = (ROOT / 'Tests/FuzzySearch/Browser/browser-tests.m').read_text()
prefix = fixture[:fixture.index('// Run the exact production occurrence-selection methods')]
helpers = fixture[fixture.index('static BOOL Spin('):fixture.index('int main(void)')]
(out / 'lifetime-probe.m').write_text(prefix + helpers + (HERE / 'lifetime-body.m').read_text())
service = (ROOT / 'Sources/Search/NVSearchService.m').read_text()
if a.repair_control:
    # Test-only counterfactual: release all cancelled callbacks on main.
    service = service.replace('if (work) nvfzf_cancel_set(work->cancel);', 'if (work) { nvfzf_cancel_set(work->cancel); [work->completion release]; work->completion = nil; }')
    service = service.replace('nvfzf_cancel_set(positions->cancel); [_positionRequests removeObjectForKey:positionKey];', 'nvfzf_cancel_set(positions->cancel); [positions->completion release]; positions->completion = nil; [_positionRequests removeObjectForKey:positionKey];')
(out / 'service.m').write_text(service)
sources = ['Sources/Search/NVFZF.c', 'ThirdParty/fzf-native/fzf.c', 'ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c',
'Sources/Search/NVSearchQuery.m', 'Sources/Search/NVSearchCorpus.m', str((out / 'service.m').relative_to(ROOT)),
'Sources/Browser/NVBrowserSession.m', str((out / 'lifetime-probe.m').relative_to(ROOT))]
flags = ['-arch','arm64','-g','-O1' if a.sanitize else '-O2','-DUTF8PROC_STATIC','-I'+str(ROOT/'ThirdParty/fzf-native'),*include_flags(ROOT)]
if a.sanitize: flags += ['-fsanitize=address,undefined','-fno-omit-frame-pointer']
objects = []
for i, path in enumerate(sources):
    obj = out / f'{i}.o'
    language = ['-fblocks','-fno-objc-arc','-Wno-deprecated-declarations','-Wno-incomplete-implementation','-Wno-protocol','-include',str(ROOT/'Config/Notation_Prefix.pch')] if path.endswith('.m') else ['-std=c11']
    subprocess.run(['xcrun','clang',*flags,*language,'-c',str(ROOT/path),'-o',str(obj)],check=True)
    objects.append(str(obj))
binary = out / 'lifetime-probe'
subprocess.run(['xcrun','clang',*flags,*objects,'-framework','Cocoa','-framework','Carbon','-o',str(binary)],check=True)
results=[]
for mode in ['literal','search','positions']:
    result=subprocess.run([str(binary),mode],capture_output=True,text=True,timeout=15,env=dict(os.environ,UBSAN_OPTIONS='halt_on_error=1'))
    record={'mode':mode,'exit_code':result.returncode,'stdout':result.stdout,'stderr':result.stderr}
    results.append(record)
    print(mode, 'exit', result.returncode, '\n'+result.stdout+result.stderr)
inputs=['Sources/Search/NVSearchService.m', 'Tests/FuzzySearch/Browser/browser-tests.m',str(HERE.relative_to(ROOT)/'lifetime-body.m'), *[s for s in sources if not s.startswith('build/')]]
record={'command':['python3',str(Path(__file__).relative_to(ROOT)),*(['--sanitize'] if a.sanitize else []),*(['--repair-control'] if a.repair_control else [])],
'head':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'results':results,'sha256':{path:hashlib.sha256((ROOT/path).read_bytes()).hexdigest() for path in inputs}}
(HERE/(variant+'-lifetime-results.json')).write_text(json.dumps(record,indent=2)+'\n')
if a.repair_control:
    assert all(r['exit_code']==0 for r in results), 'repair control did not remove the lifetime failure'
else:
    assert results[0]['exit_code']==0, 'literal cancellation regression'
    assert all(r['exit_code']!=0 and 'SESSION DEALLOC: main=0' in r['stdout'] for r in results[1:]), 'expected worker-side destruction was not reproduced'
