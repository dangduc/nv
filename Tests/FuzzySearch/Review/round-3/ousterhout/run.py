#!/usr/bin/env python3
"""Positive ownership checks for callback reentry and queued mapping continuations."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
sys.path.insert(0, str(ROOT / 'Tests'))
from compiler_support import include_flags


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sanitize', action='store_true')
    parser.add_argument('--arch', choices=['arm64', 'x86_64'], default=platform.machine())
    parser.add_argument('--build-only', action='store_true')
    args = parser.parse_args()
    variant = args.arch + ('-sanitize' if args.sanitize else '-native')
    out = ROOT / 'build/FuzzySearchReview/round-3/ousterhout' / variant
    out.mkdir(parents=True, exist_ok=True)
    snapshot = out / 'source'
    sources = [
        'Sources/Search/NVFZF.c', 'ThirdParty/fzf-native/fzf.c',
        'ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c',
        'Sources/Search/NVSearchQuery.m', 'Sources/Search/NVSearchCorpus.m',
        'Sources/Search/NVSearchService.m', 'Sources/Browser/NVBrowserSession.m',
    ]
    inputs = sources + [str(p.relative_to(ROOT)) for p in (ROOT / 'Sources/Search').glob('*.h')]
    inputs += ['Sources/Browser/NVBrowserSession.h', 'Tests/FuzzySearch/Browser/browser-tests.m',
               'Config/Notation_Prefix.pch', 'Tests/compiler_support.py',
               'ThirdParty/fzf-native/fzf.h', 'ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.h',
               'ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc_data.c',
               str(HERE.relative_to(ROOT) / 'probe.m'), str(HERE.relative_to(ROOT) / 'run.py')]
    data = {path: (ROOT / path).read_bytes() for path in inputs}
    before = {path: hashlib.sha256(content).hexdigest() for path, content in data.items()}
    for path, content in data.items():
        target = snapshot / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
    fixture = data['Tests/FuzzySearch/Browser/browser-tests.m'].decode()
    prefix = fixture[:fixture.index('// Run the exact production occurrence-selection methods')]
    helpers = fixture[fixture.index('static BOOL Spin('):fixture.index('int main(void)')]
    generated = out / 'probe.m'
    generated.write_text(prefix + helpers + data[str(HERE.relative_to(ROOT) / 'probe.m')].decode())
    flags = ['-arch', args.arch, '-g', '-O1' if args.sanitize else '-O2', '-DUTF8PROC_STATIC',
             '-I' + str(snapshot / 'ThirdParty/fzf-native'), '-I' + str(ROOT / 'ThirdParty/fzf-native'),
             '-I' + str(snapshot / 'Sources/Search'), '-I' + str(snapshot / 'Sources/Browser'), *include_flags(ROOT)]
    if args.sanitize:
        flags += ['-fsanitize=address,undefined', '-fno-omit-frame-pointer']
    objects = []
    compiler_log = []
    for index, path in enumerate([snapshot / path for path in sources] + [generated]):
        obj = out / f'{index}.o'
        language = ['-fblocks', '-fno-objc-arc', '-Wno-deprecated-declarations', '-Wno-incomplete-implementation',
                    '-Wno-protocol', '-include', str(snapshot / 'Config/Notation_Prefix.pch')] if path.suffix == '.m' else ['-std=c11']
        result = subprocess.run(['xcrun', 'clang', *flags, *language, '-c', str(path), '-o', str(obj)], capture_output=True, text=True)
        compiler_log.append(result.stdout + result.stderr)
        (out / 'compile.log').write_text(''.join(compiler_log))
        if result.returncode:
            print(result.stdout + result.stderr, end='')
            result.check_returncode()
        objects.append(str(obj))
    binary = out / 'ownership-probe'
    subprocess.run(['xcrun', 'clang', *flags, *objects, '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(binary)], check=True)
    if args.build_only:
        print('Built ownership probe:', binary)
        return
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=40,
                            env=dict(os.environ, UBSAN_OPTIONS='halt_on_error=1'))
    print(result.stdout + result.stderr, end='')
    changed = [path for path, digest in before.items() if hashlib.sha256((ROOT / path).read_bytes()).hexdigest() != digest]
    record = {'command': sys.argv, 'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'arch': args.arch, 'sanitized': args.sanitize, 'exit_code': result.returncode,
              'stdout': result.stdout, 'stderr': result.stderr, 'changed_during_run': changed, 'sha256': before}
    (out / 'results.json').write_text(json.dumps(record, indent=2) + '\n')
    if changed:
        raise RuntimeError('Inputs changed during the run; snapshot results need a new stable run: ' + ', '.join(changed))
    result.check_returncode()


if __name__ == '__main__':
    main()
