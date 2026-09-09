#!/usr/bin/env python3
"""Measure exact tag-cache methods and check bounded appearance/font reuse."""
from pathlib import Path
import argparse
import json
import subprocess

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
OUTPUT = ROOT / 'build/NotesListAppearanceReview/round1/luu'
BASE = '878961a'
SOURCE = 'Sources/Browser/LabelsListController.m'


def method(source, selector):
    start = source.index(selector)
    return source[start:source.index('\n}\n', start) + 3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--negative-controls', action='store_true')
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    current = (ROOT / SOURCE).read_text()
    baseline = subprocess.check_output(['git', 'show', f'{BASE}:{SOURCE}'], cwd=ROOT, text=True)
    selector = '- (NSImage*)cachedLabelImageForWord:'
    for name, source in [('current', current), ('baseline', baseline)]:
        (OUTPUT / f'{name}.inc').write_text(method(source, selector))
    (OUTPUT / 'invalidate.inc').write_text(method(current, '- (void)invalidateCachedLabelImages'))
    binary = OUTPUT / 'probe'
    command = ['xcrun', 'clang', '-x', 'objective-c', '-arch', 'arm64', '-O2', '-fno-objc-arc',
               '-Wno-deprecated-declarations', '-I', str(OUTPUT),
               '-I', str(ROOT / 'Sources/Utilities'), str(HERE / 'probe.m'),
               str(ROOT / 'Sources/Utilities/NSBezierPath_NV.m'), '-framework', 'Cocoa',
               '-o', str(binary)]
    compiled = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    (OUTPUT / 'compile.txt').write_text(compiled.stdout + compiled.stderr)
    compiled.check_returncode()
    result = subprocess.run([str(binary)], cwd=ROOT, text=True, capture_output=True, timeout=90)
    (OUTPUT / 'output.txt').write_text(result.stdout + result.stderr)
    print(result.stdout, end='')
    if result.stderr:
        print(result.stderr, end='')
    result.check_returncode()
    json.loads(result.stdout.splitlines()[-1])
    if args.negative_controls:
        original = method(current, selector)
        mutations = [
            ('omit-color', '@[[aWord lowercaseString], @(isHighlighted), fillColor]',
             '@[[aWord lowercaseString], @(isHighlighted)]',
             'light and dark normal tags use different raster images'),
            ('bypass-cache', 'NSImage *img = [labelImages objectForKey:imgKey];',
             'NSImage *img = nil;',
             'repeated appearance draw reuses the original raster'),
        ]
        try:
            for name, old, new, message in mutations:
                assert original.count(old) == 1, f'Expected one mutation site: {name}'
                (OUTPUT / 'current.inc').write_text(original.replace(old, new))
                rebuilt = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
                rebuilt.check_returncode()
                rejected = subprocess.run([str(binary)], cwd=ROOT, text=True,
                                          capture_output=True, timeout=30)
                (OUTPUT / f'{name}.txt').write_text(rejected.stdout + rejected.stderr)
                assert rejected.returncode != 0 and message in rejected.stderr, rejected
                print(f'PASS: {name} mutation fails its cache assertion')
        finally:
            (OUTPUT / 'current.inc').write_text(original)
            subprocess.run(command, cwd=ROOT, check=True, capture_output=True)


if __name__ == '__main__':
    main()
