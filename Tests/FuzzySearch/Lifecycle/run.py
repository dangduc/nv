#!/usr/bin/env python3
"""Positive production browser/session callback-lifetime checks; no desktop needed."""
import argparse, hashlib, json, os, platform
from pathlib import Path
import subprocess, sys
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / 'Tests'))
from compiler_support import include_flags
p = argparse.ArgumentParser()
p.add_argument('--sanitize', action='store_true')
p.add_argument('--arch', choices=['arm64', 'x86_64'], default=platform.machine())
p.add_argument('--build-only', action='store_true')
a = p.parse_args()
variant = a.arch + ('-sanitize' if a.sanitize else '-native')
out = ROOT / 'build/FuzzySearchLifecycle' / variant
out.mkdir(parents=True, exist_ok=True)
fixture = (ROOT / 'Tests/FuzzySearch/Browser/browser-tests.m').read_text()
prefix = fixture[:fixture.index('// Run the exact production occurrence-selection methods')]
helpers = fixture[fixture.index('static BOOL Spin('):fixture.index('int main(void)')]
(out / 'probe.m').write_text(prefix + helpers + (HERE / 'probe.m').read_text())
sources = ['Sources/Search/NVFZF.c', 'ThirdParty/fzf-native/fzf.c', 'ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c',
'Sources/Search/NVSearchQuery.m', 'Sources/Search/NVSearchCorpus.m', 'Sources/Search/NVSearchService.m',
'Sources/Browser/NVBrowserSession.m', str((out / 'probe.m').relative_to(ROOT))]
flags = ['-arch',a.arch,'-g','-O1' if a.sanitize else '-O2','-DUTF8PROC_STATIC','-I'+str(ROOT/'ThirdParty/fzf-native'),*include_flags(ROOT)]
if a.sanitize: flags += ['-fsanitize=address,undefined','-fno-omit-frame-pointer']
objects = []
for i, path in enumerate(sources):
    obj = out / f'{i}.o'
    language = ['-fblocks','-fno-objc-arc','-Wno-deprecated-declarations','-Wno-incomplete-implementation','-Wno-protocol','-include',str(ROOT/'Config/Notation_Prefix.pch')] if path.endswith('.m') else ['-std=c11']
    subprocess.run(['xcrun','clang',*flags,*language,'-c',str(ROOT/path),'-o',str(obj)],check=True)
    objects.append(str(obj))
binary = out / 'lifecycle-probe'
subprocess.run(['xcrun','clang',*flags,*objects,'-framework','Cocoa','-framework','Carbon','-o',str(binary)],check=True)
if a.build_only:
    print('Built lifecycle probe:', binary)
    raise SystemExit(0)
result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30,
                        env=dict(os.environ, UBSAN_OPTIONS='halt_on_error=1'))
print(result.stdout + result.stderr, end='')
inputs = [path for path in sources if not path.startswith('build/')] + [str(HERE.relative_to(ROOT)/'probe.m'), 'Tests/FuzzySearch/Browser/browser-tests.m']
record = {'command':sys.argv, 'head':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
          'arch':a.arch, 'exit_code':result.returncode, 'stdout':result.stdout, 'stderr':result.stderr,
          'sha256':{path:hashlib.sha256((ROOT/path).read_bytes()).hexdigest() for path in inputs}}
(out/'results.json').write_text(json.dumps(record, indent=2)+'\n')
if result.returncode: raise SystemExit(result.returncode)
