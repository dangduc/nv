#!/usr/bin/env python3
"""Bounded round-three checks against a snapshot of the complete search service."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
parser = argparse.ArgumentParser()
parser.add_argument('--sanitize', action='store_true')
args = parser.parse_args()
mode = 'sanitize' if args.sanitize else 'native'
out = ROOT / 'build/FuzzySearchReview/round-3/torvalds' / mode
out.mkdir(parents=True, exist_ok=True)
sources = ['Sources/Search/NVFZF.c', 'ThirdParty/fzf-native/fzf.c', 'ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c',
           'Sources/Search/NVSearchQuery.m', 'Sources/Search/NVSearchCorpus.m']
service = 'Sources/Search/NVSearchService.m'
inspected = sources + [service, 'Sources/Search/NVFZF.h', 'Sources/Search/NVSearchService.h', 'Sources/Search/NVSearchQuery.h',
                       'Sources/Search/NVSearchCorpus.h', str((HERE / 'probe.m').relative_to(ROOT)), str((HERE / 'run.py').relative_to(ROOT))]
inspected += ['Sources/Search/NativeRanking.inc', 'Sources/Search/NativePattern.inc']
inspected += sorted(str(path.relative_to(ROOT)) for path in (ROOT / 'ThirdParty/fzf-native').rglob('*')
                    if path.is_file() and (path.suffix in ('.h', '.inc') or path.name == 'utf8proc_data.c'))
hashes = {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in inspected}
(out / 'reviewed-service.m').write_bytes((ROOT / service).read_bytes())
baseline = subprocess.check_output(['git', 'show', '11f571f:' + service], cwd=ROOT)
assert hashlib.sha256(baseline).hexdigest() == hashes[service], 'The reviewed service differs from mapping checkpoint 11f571f.'
record = {'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
          'mapping_checkpoint': '11f571f', 'mode': mode, 'utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'sources': hashes, 'service_snapshot': str(out / 'reviewed-service.m'),
          'service_snapshot_sha256': hashlib.sha256((out / 'reviewed-service.m').read_bytes()).hexdigest(), 'commands': []}

def run(command, env=None):
    result = subprocess.run(list(map(str, command)), cwd=ROOT, text=True, capture_output=True, timeout=60, env=env)
    record['commands'].append({'command': list(map(str, command)), 'exit': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr})
    print(result.stdout + result.stderr, end='', flush=True)
    if result.returncode:
        (HERE / (mode + '-results.json')).write_text(json.dumps(record, indent=2) + '\n')
        raise SystemExit(result.returncode)

run(['sw_vers']); run(['xcodebuild', '-version'])
flags = ['-g', '-O1' if args.sanitize else '-O2', '-arch', 'arm64', '-mmacosx-version-min=11.0', '-DUTF8PROC_STATIC',
         '-I' + str(ROOT / 'Sources/Search'), '-I' + str(ROOT / 'ThirdParty/fzf-native'), '-I' + str(out)]
if args.sanitize: flags += ['-fsanitize=address,undefined', '-fno-omit-frame-pointer']
objects = []
for index, source in enumerate(sources + [str((HERE / 'probe.m').relative_to(ROOT))]):
    obj = out / f'{index}.o'; objects.append(obj)
    language = ['-fblocks', '-fno-objc-arc', '-Wall', '-Werror'] if source.endswith('.m') else ['-std=c11']
    run(['xcrun', 'clang', *flags, *language, '-c', ROOT / source, '-o', obj])
binary = out / 'probe'
run(['xcrun', 'clang', *flags, *objects, '-framework', 'Foundation', '-o', binary])
run([binary], dict(os.environ, UBSAN_OPTIONS='halt_on_error=1'))
record['changed_sources'] = [path for path, expected in hashes.items() if hashlib.sha256((ROOT / path).read_bytes()).hexdigest() != expected]
(HERE / (mode + '-results.json')).write_text(json.dumps(record, indent=2) + '\n')
assert not record['changed_sources'], record['changed_sources']
