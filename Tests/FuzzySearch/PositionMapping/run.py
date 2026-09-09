#!/usr/bin/env python3
"""Build the bounded position-mapping fixture against the production core."""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
p = argparse.ArgumentParser()
p.add_argument('--sanitize', action='store_true')
p.add_argument('--arch', choices=['arm64', 'x86_64'], default=platform.machine())
p.add_argument('--build-only', action='store_true')
p.add_argument('--mutation', choices=['no-yield'])
a = p.parse_args()
OUT = ROOT / 'build/FuzzySearchPositionMapping' / (a.arch + ('-sanitize' if a.sanitize else '-native') + ('-' + a.mutation if a.mutation else ''))
OUT.mkdir(parents=True, exist_ok=True)
service = (ROOT / 'Sources/Search/NVSearchService.m').read_text()
production_service_hash = hashlib.sha256(service.encode()).hexdigest()
start = service.index('/* Borrowed offsets and string')
end = service.index('NSArray *NVSearchOriginalRanges(', start)
(OUT / 'mapper.inc').write_text(service[start:end])
if a.mutation:
    before = 'sequences == 4096 ||\n            (!(sequences & 63) && CFAbsoluteTimeGetCurrent() >= deadline)'
    assert service.count(before) == 1
    service = service.replace(before, 'sequences == NSUIntegerMax ||\n            (NO && CFAbsoluteTimeGetCurrent() >= deadline)')
native_call = 'if (status == NVFZF_OK) status = nvfzf_positions_terms(_engine, (NVFZFCandidate){[bytes bytes], [bytes length]}, terms, [[work->query terms] count], work->cancel, &work->output);'
assert service.count(native_call) == 1
service = '#include <time.h>\n#include <stdint.h>\nextern void NVPositionMappingNativeTime(uint64_t nanoseconds);\n' + service.replace(native_call, 'uint64_t nativeStart = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);\n        ' + native_call + '\n        NVPositionMappingNativeTime(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - nativeStart);')
(OUT / 'NVSearchService.m').write_text(service)
flags = ['-arch', a.arch, '-g', '-O1' if a.sanitize else '-O2', '-mmacosx-version-min=10.13', '-DUTF8PROC_STATIC', '-I'+str(OUT), '-I'+str(ROOT/'Sources/Search'), '-I'+str(ROOT/'ThirdParty/fzf-native')]
if a.sanitize:
    flags += ['-fsanitize=address,undefined', '-fno-omit-frame-pointer']
sources = ['Sources/Search/NVFZF.c', 'ThirdParty/fzf-native/fzf.c', 'ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c', 'Sources/Search/NVSearchQuery.m', 'Sources/Search/NVSearchCorpus.m', 'Sources/Search/NVSearchService.m', 'Tests/FuzzySearch/PositionMapping/probe.m']
objects = []
for index, source in enumerate(sources):
    obj = OUT / f'{index}.o'
    language = ['-fblocks', '-fno-objc-arc', '-Wall', '-Wextra', '-Wno-unused-parameter', '-Werror'] if source.endswith('.m') else ['-std=c11']
    src = OUT / 'NVSearchService.m' if source == 'Sources/Search/NVSearchService.m' else ROOT/source
    subprocess.run(['xcrun', 'clang', *flags, *language, '-c', str(src), '-o', str(obj)], check=True)
    objects.append(str(obj))
exe = OUT / 'probe'
subprocess.run(['xcrun', 'clang', *flags, *objects, '-framework', 'Foundation', '-o', str(exe)], check=True)
if a.build_only:
    print('BUILT:', exe)
    raise SystemExit(0)
env = dict(os.environ)
if a.sanitize:
    env['UBSAN_OPTIONS'] = 'halt_on_error=1'
result = subprocess.run([str(exe)], text=True, capture_output=True, timeout=60, env=env)
print(result.stdout, end='')
print(result.stderr, end='')
record = {'arch': a.arch, 'sanitized': a.sanitize, 'mutation': a.mutation,
          'exit_code': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr,
          'os': subprocess.check_output(['sw_vers'], text=True).strip(),
          'toolchain': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
          'production_service_sha256': production_service_hash,
          'compiled_service_sha256': hashlib.sha256(service.encode()).hexdigest(),
          'sha256': {source: hashlib.sha256((ROOT/source).read_bytes()).hexdigest() for source in sources if source != 'Sources/Search/NVSearchService.m'}}
(OUT / 'results.json').write_text(json.dumps(record, indent=2) + '\n')
raise SystemExit(result.returncode)
