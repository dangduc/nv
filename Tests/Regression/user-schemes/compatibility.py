#!/usr/bin/env python3
"""Compile the real availability guard, then simulate its older-AppKit branch."""
import argparse
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--negative-controls', action='store_true')
args = parser.parse_args()
source = (ROOT / 'Sources/Browser/AppController_BrowserUI.m').read_text()
start = source.index('- (void)browserAppearanceChanged {')
method = source[start:source.index('\n}', start) + 2]
guard = 'if (@available(macOS 11.0, *))'
if method.count(guard) != 1:
    raise SystemExit('FAIL: the drawing appearance API must have one macOS 11.0 guard')

with tempfile.TemporaryDirectory(prefix='nvalt-appearance-compatibility-') as directory:
    output = Path(directory)
    include = output / 'appearance.inc'
    binary = output / 'compatibility'
    flags = ['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13',
             '-fno-objc-arc', '-fblocks', '-Werror=unguarded-availability-new',
             '-Wno-deprecated-declarations', '-I', str(output), str(HERE / 'compatibility.m')]
    include.write_text(method)
    subprocess.run([*flags, '-fsyntax-only'], check=True)
    print('PASS: the unchanged production method compiles with availability errors enabled for macOS 10.13', flush=True)

    def run_case(name, text, positive):
        include.write_text(text.replace(guard, 'if (NVUseModernAppearanceAPI)'))
        # Only the forced branch lacks a compiler availability guard. The first
        # compilation above checked the original production method unchanged.
        subprocess.run([*flags, '-Wno-unguarded-availability-new', '-framework', 'Cocoa',
                        '-o', str(binary)], check=True)
        result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
        print(result.stdout + result.stderr, end='', flush=True)
        if positive and result.returncode:
            raise SystemExit(result.returncode)
        if not positive and result.returncode == 0:
            raise SystemExit('FAIL: mutation unexpectedly passed: ' + name)
        if not positive:
            print('REJECTED: ' + name, flush=True)

    run_case('production fallback', method, True)
    if args.negative_controls:
        include.write_text(method.replace(guard, 'if (@available(macOS 10.14, *))'))
        result = subprocess.run([*flags, '-fsyntax-only'], capture_output=True, text=True)
        if result.returncode == 0 or 'performAsCurrentDrawingAppearance:' not in result.stderr:
            raise SystemExit('FAIL: the old macOS 10.14 guard escaped the availability check')
        print('REJECTED: macOS 10.14 guard for the macOS 11 selector', flush=True)
        mutant = method.replace('} @finally {',
            '} @catch (NSException *exception) { [previousAppearance release]; @throw; } {')
        if mutant == method:
            raise SystemExit('FAIL: the missing-exception-restoration mutation no longer applies')
        run_case('restoration only after successful updates', mutant, False)
