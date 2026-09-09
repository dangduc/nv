#!/usr/bin/env python3
"""Run new range and UTF-16 boundary checks against complete production files."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--sanitize', action='store_true')
    p.add_argument('--intel-compile-only', action='store_true')
    args = p.parse_args()
    mode = 'intel-compile-only' if args.intel_compile_only else ('sanitize' if args.sanitize else 'native')
    out = ROOT / 'build/FuzzySearchReview/round-2/torvalds' / mode
    out.mkdir(parents=True, exist_ok=True)
    sources = ['Sources/Search/NVFZF.c', 'ThirdParty/fzf-native/fzf.c', 'ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c',
               'Sources/Search/NVSearchQuery.m', 'Sources/Search/NVSearchCorpus.m', 'Sources/Search/NVSearchService.m']
    inspected = sources + ['Sources/Search/NVSearchQuery.h', 'Sources/Search/NVSearchService.h', 'Sources/Search/NVSearchCorpus.h',
                           'Sources/Editor/LinkingEditor.m', 'Sources/Browser/AppController_Search.m',
                           str((HERE / 'probe.m').relative_to(ROOT)), str((HERE / 'run.py').relative_to(ROOT))]
    hashes = {s: hashlib.sha256((ROOT / s).read_bytes()).hexdigest() for s in inspected}
    record = {'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'mode': mode, 'sources': hashes, 'commands': []}

    def run(cmd, env=None):
        print('+', ' '.join(map(str, cmd)), flush=True)
        result = subprocess.run(list(map(str, cmd)), cwd=ROOT, text=True, capture_output=True, timeout=120, env=env)
        record['commands'].append({'command': list(map(str, cmd)), 'exit': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr})
        print(result.stdout + result.stderr, end='', flush=True)
        if result.returncode:
            (HERE / (mode + '-results.json')).write_text(json.dumps(record, indent=2) + '\n')
            raise SystemExit(result.returncode)

    run(['sw_vers']); run(['xcodebuild', '-version'])
    flags = ['-g', '-O1' if args.sanitize else '-O2', '-DUTF8PROC_STATIC', '-I' + str(ROOT / 'Sources/Search'), '-I' + str(ROOT / 'ThirdParty/fzf-native'),
             '-arch', 'x86_64' if args.intel_compile_only else 'arm64', '-mmacosx-version-min=10.13' if args.intel_compile_only else '-mmacosx-version-min=11.0']
    if args.sanitize: flags += ['-fsanitize=address,undefined', '-fno-omit-frame-pointer']
    objects = []
    for i, source in enumerate(sources + [str((HERE / 'probe.m').relative_to(ROOT))]):
        obj = out / f'{i}.o'; objects.append(obj)
        language = ['-fblocks', '-fno-objc-arc', '-Wall', '-Werror'] if source.endswith('.m') else ['-std=c11']
        run(['xcrun', 'clang', *flags, *language, '-c', ROOT / source, '-o', obj])
    executable = out / 'boundary-review'
    run(['xcrun', 'clang', *flags, *objects, '-framework', 'Foundation', '-o', executable])
    if not args.intel_compile_only:
        run([executable], dict(os.environ, UBSAN_OPTIONS='halt_on_error=1'))
    record['changed_sources'] = [s for s, h in hashes.items() if hashlib.sha256((ROOT / s).read_bytes()).hexdigest() != h]
    (HERE / (mode + '-results.json')).write_text(json.dumps(record, indent=2) + '\n')
    if record['changed_sources']: raise SystemExit('A reviewed source changed during execution.')
    print('PASS:', mode, '(Intel execution disabled)' if args.intel_compile_only else '')


if __name__ == '__main__':
    main()
