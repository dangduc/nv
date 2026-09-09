#!/usr/bin/env python3
"""Run production coordinator methods with real browser sessions and native fzf."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
sys.path.insert(0, str(ROOT / 'Tests'))
from compiler_support import include_flags
p = argparse.ArgumentParser()
p.add_argument('--sanitize', action='store_true')
a = p.parse_args()
out = ROOT / 'build/FuzzySearchReview/round-1/ousterhout' / ('coordinator-sanitize' if a.sanitize else 'coordinator-native')
out.mkdir(parents=True, exist_ok=True)
fixture = (ROOT / 'Tests/FuzzySearch/Browser/browser-tests.m').read_text()
prefix = fixture[:fixture.index('// Run the exact production occurrence-selection methods')]
helpers = fixture[fixture.index('static BOOL Spin('):fixture.index('int main(void)')]
(out / 'coordinator-probe.m').write_text(prefix + helpers + (HERE / 'coordinator-probe-body.m').read_text())
production = (ROOT / 'Sources/Application/NVApplicationController.m').read_text()
methods = []
for signature in ['- (NVSearchNoteSnapshot *)searchSnapshotForNote:', '- (void)invalidateBrowserSearches',
                  '- (void)searchableNoteDidChange:', '- (void)searchableNoteWasRemoved:',
                  '- (void)refreshBrowsers', '- (void)scheduleBrowserRefresh']:
    start = production.index(signature)
    methods.append(production[start:production.index('\n}', start) + 2])
(out / 'coordinator-methods.inc').write_text('\n'.join(methods))
flags = ['-arch', 'arm64', '-g', '-O1' if a.sanitize else '-O2', '-DUTF8PROC_STATIC',
         '-I' + str(out), '-I' + str(ROOT / 'ThirdParty/fzf-native'), *include_flags(ROOT)]
if a.sanitize:
    flags += ['-fsanitize=address,undefined', '-fno-omit-frame-pointer']
sources = ['Sources/Search/NVFZF.c', 'ThirdParty/fzf-native/fzf.c',
           'ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c', 'Sources/Search/NVSearchQuery.m',
           'Sources/Search/NVSearchCorpus.m', 'Sources/Search/NVSearchService.m',
           'Sources/Browser/NVBrowserSession.m', str((out / 'coordinator-probe.m').relative_to(ROOT))]
objects = []
for index, source in enumerate(sources):
    obj = out / f'{index}.o'
    language = ['-fblocks', '-fno-objc-arc', '-Wno-deprecated-declarations', '-Wno-incomplete-implementation',
                '-Wno-protocol', '-include', str(ROOT / 'Config/Notation_Prefix.pch')] if source.endswith('.m') else ['-std=c11']
    subprocess.run(['xcrun', 'clang', *flags, *language, '-c', str(ROOT / source), '-o', str(obj)], check=True)
    objects.append(str(obj))
binary = out / 'coordinator-probe'
subprocess.run(['xcrun', 'clang', *flags, *objects, '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(binary)], check=True)
environment = dict(os.environ)
if a.sanitize:
    environment['UBSAN_OPTIONS'] = 'halt_on_error=1'
result = subprocess.run([str(binary)], capture_output=True, text=True, env=environment, timeout=30)
print(result.stdout, end='')
print(result.stderr, end='')
inputs = ['Sources/Application/NVApplicationController.m', 'Tests/FuzzySearch/Browser/browser-tests.m',
          str(HERE.relative_to(ROOT) / 'coordinator-probe-body.m'), *sources[:-1]]
record = {'command': ['python3', str(Path(__file__).relative_to(ROOT)), *(['--sanitize'] if a.sanitize else [])],
          'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
          'exit_code': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr,
          'sha256': {source: hashlib.sha256((ROOT / source).read_bytes()).hexdigest() for source in inputs}}
(HERE / ('coordinator-sanitize-results.json' if a.sanitize else 'coordinator-native-results.json')).write_text(json.dumps(record, indent=2) + '\n')
raise SystemExit(result.returncode)
