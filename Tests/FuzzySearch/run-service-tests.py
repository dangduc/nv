#!/usr/bin/env python3
"""Build and run the Foundation search boundary without a desktop session."""
import argparse
import os
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser()
p.add_argument('--sanitize', action='store_true')
p.add_argument('--arch', choices=['arm64', 'x86_64'])
p.add_argument('--build-only', action='store_true')
p.add_argument('--benchmark', action='store_true')
p.add_argument('--long-line-only', action='store_true', help='Benchmark only the8MiB Unicode cancellation case.')
p.add_argument('--timeout', type=float, default=90)
a = p.parse_args()
out = ROOT / 'build' / 'FuzzySearchServiceTests' / ('sanitize' if a.sanitize else (a.arch or 'native'))
out.mkdir(parents=True, exist_ok=True)
flags = ['-g', '-O1' if a.sanitize else '-O2', '-mmacosx-version-min=10.13', '-DUTF8PROC_STATIC', '-I' + str(ROOT/'Sources/Search'), '-I' + str(ROOT/'ThirdParty/fzf-native')]
if a.arch: flags += ['-arch', a.arch]
if a.sanitize: flags += ['-fsanitize=address,undefined', '-fno-omit-frame-pointer']
sources = ['Sources/Search/NVFZF.c', 'ThirdParty/fzf-native/fzf.c', 'ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c', 'Sources/Search/NVSearchQuery.m', 'Sources/Search/NVSearchCorpus.m', 'Sources/Search/NVSearchService.m', 'Tests/FuzzySearch/service-benchmark.m' if a.benchmark else 'Tests/FuzzySearch/service-tests.m']
objects = []
for i, source in enumerate(sources):
    obj = out / f'{i}.o'
    objc = source.endswith('.m')
    subprocess.run(['xcrun', 'clang', *flags, *(['-fblocks', '-fno-objc-arc', '-Wall', '-Werror'] if objc else ['-std=c11']), '-c', str(ROOT/source), '-o', str(obj)], check=True)
    objects.append(str(obj))
exe = out / ('service-benchmark' if a.benchmark else 'service-tests')
subprocess.run(['xcrun', 'clang', *flags, *objects, '-framework', 'Foundation', '-o', str(exe)], check=True)
if not a.build_only:
    environment = dict(os.environ)
    if a.sanitize:
        environment['UBSAN_OPTIONS'] = 'halt_on_error=1'
    process = subprocess.Popen([str(exe), *(['--long-line-only'] if a.long_line_only else [])], env=environment)
    try:
        code = process.wait(timeout=a.timeout)
    except subprocess.TimeoutExpired:
        process.kill()
        raise SystemExit(f'Timed out; kill sent to PID {process.pid}. No completed test result.')
    if code:
        raise SystemExit(code)
else:
    print(f'BUILT: {exe}')
