#!/usr/bin/env python3
"""Check native active selection and inline editing with an actual key window."""
from pathlib import Path
import argparse
import plistlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build/NotesListAppearanceReview/round2/contrarian'


def method(path, prefix):
    source = (ROOT / path).read_text()
    start = source.index(prefix)
    return source[start:source.index('\n}', start) + 2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--negative-control', action='store_true')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    delegate = method('Sources/Browser/AppController.m', '- (void)tableView:(NSTableView *)aTableView willDisplayCell:')
    (OUT / 'delegate.inc').write_text(delegate)
    preview = (ROOT / 'Sources/Utilities/NSString_CustomTruncation.m').read_text()
    (OUT / 'preview.m').write_text(preview)
    app = OUT / 'Selection Review.app'
    binary = app / 'Contents/MacOS/probe'
    binary.parent.mkdir(parents=True, exist_ok=True)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleExecutable': 'probe', 'CFBundleIdentifier': 'org.nvalt.review.selection',
        'CFBundleName': 'Selection Review', 'CFBundlePackageType': 'APPL',
        'NSHighResolutionCapable': True,
    }))
    command = ['xcrun', 'clang', '-x', 'objective-c', '-arch', 'arm64',
               '-include', 'Cocoa/Cocoa.h', '-include', 'Carbon/Carbon.h',
               '-Dforce_inline=__inline__', '-DCOMPILE_ASSERT(X,N)=_Static_assert(X,#N)',
               '-DIsLeopardOrLater=1', '-DIsSnowLeopardOrLater=1',
               '-fno-objc-arc', '-Wno-incomplete-implementation', '-Wno-deprecated-declarations']
    for directory in sorted((ROOT / 'Sources').iterdir()):
        if directory.is_dir():
            command += ['-I', str(directory)]
    command += ['-I', str(OUT), str(HERE / 'probe.m'),
                str(OUT / 'preview.m'),
                'Sources/Utilities/BufferUtils.c', 'Sources/Utilities/NSBezierPath_NV.m',
                '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(binary)]

    def compile_probe():
        result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=60)
        (OUT / 'compile.log').write_text(result.stdout + result.stderr)
        if result.returncode:
            print(result.stdout + result.stderr)
        result.check_returncode()

    def run_probe(name, baseline=False):
        directory = OUT / name
        directory.mkdir(exist_ok=True)
        result = subprocess.run([str(binary), str(directory)] + (['base'] if baseline else []), cwd=ROOT, text=True,
                                capture_output=True, timeout=30)
        (OUT / f'{name}.log').write_text(result.stdout + result.stderr)
        print(result.stdout + result.stderr, end='')
        return result

    compile_probe()
    run_probe('normal').check_returncode()
    base_source = subprocess.check_output(['git', 'show', '878961a:Sources/Browser/AppController.m'], cwd=ROOT, text=True)
    start = base_source.index('- (void)tableView:(NSTableView *)aTableView willDisplayCell:')
    base_delegate = base_source[start:base_source.index('\n}', start) + 2]
    assert base_delegate == delegate, 'The field-color delegate comparison requires unchanged source.'
    base_preview = subprocess.check_output(['git', 'show', '878961a:Sources/Utilities/NSString_CustomTruncation.m'], cwd=ROOT, text=True)
    try:
        (OUT / 'delegate.inc').write_text(base_delegate)
        (OUT / 'preview.m').write_text(base_preview)
        compile_probe()
        run_probe('base-light', baseline=True).check_returncode()
        current = [item for item in json.loads((OUT / 'normal/editors.json').read_text()) if not item['dark']]
        base = json.loads((OUT / 'base-light/editors.json').read_text())
        assert current == base, (current, base)
        print('PASS: both light inline-editor observations exactly match the base fixture')
    finally:
        (OUT / 'delegate.inc').write_text(delegate)
        (OUT / 'preview.m').write_text(preview)
        compile_probe()
    if args.negative_control:
        obsolete = delegate.replace('[NSColor labelColor]', '[NSColor blackColor]')
        assert obsolete != delegate
        try:
            (OUT / 'delegate.inc').write_text(obsolete)
            compile_probe()
            bad = run_probe('black-title')
            assert bad.returncode != 0 and 'unselected title glyphs contrast' in bad.stderr, bad
            print('PASS: fixed black title mutation fails the dark native glyph assertion')
        finally:
            (OUT / 'delegate.inc').write_text(delegate)
            compile_probe()


if __name__ == '__main__':
    main()
