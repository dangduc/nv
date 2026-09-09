#!/usr/bin/env python3
"""Compile production search files and run the ownership review probe."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
p = argparse.ArgumentParser()
p.add_argument('--sanitize', action='store_true')
a = p.parse_args()
out = ROOT / 'build/FuzzySearchReview/round-1/ousterhout' / ('sanitize' if a.sanitize else 'native')
out.mkdir(parents=True, exist_ok=True)
sources = ['Sources/Search/NVFZF.c', 'ThirdParty/fzf-native/fzf.c',
           'ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c', 'Sources/Search/NVSearchQuery.m',
           'Sources/Search/NVSearchCorpus.m', 'Sources/Search/NVSearchService.m',
           str(HERE.relative_to(ROOT) / 'ownership-probe.m')]
flags = ['-arch', 'arm64', '-g', '-O1' if a.sanitize else '-O2', '-DUTF8PROC_STATIC',
         '-I' + str(ROOT / 'Sources/Search'), '-I' + str(ROOT / 'ThirdParty/fzf-native')]
if a.sanitize:
    flags += ['-fsanitize=address,undefined', '-fno-omit-frame-pointer']
objects = []
for index, source in enumerate(sources):
    obj = out / f'{index}.o'
    language = ['-fblocks', '-fno-objc-arc', '-Wall', '-Werror'] if source.endswith('.m') else ['-std=c11']
    subprocess.run(['xcrun', 'clang', *flags, *language, '-c', str(ROOT / source), '-o', str(obj)], check=True)
    objects.append(str(obj))
binary = out / 'ownership-probe'
subprocess.run(['xcrun', 'clang', *flags, *objects, '-framework', 'Foundation', '-o', str(binary)], check=True)
environment = dict(os.environ)
if a.sanitize:
    environment['UBSAN_OPTIONS'] = 'halt_on_error=1'
result = subprocess.run([str(binary)], capture_output=True, text=True, env=environment, timeout=30)
print(result.stdout, end='')
print(result.stderr, end='')
record = {'command': ['python3', str(Path(__file__).relative_to(ROOT)), *(['--sanitize'] if a.sanitize else [])],
          'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
          'exit_code': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr,
          'sha256': {source: hashlib.sha256((ROOT / source).read_bytes()).hexdigest() for source in sources}}
(HERE / ('sanitize-results.json' if a.sanitize else 'native-results.json')).write_text(json.dumps(record, indent=2) + '\n')
raise SystemExit(result.returncode)
