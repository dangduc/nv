#!/usr/bin/env python3
"""Native cells, loading text, and legacy scroller evidence for appearance review."""
from pathlib import Path
import argparse
import subprocess

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build/NotesListAppearanceReview/round1/contrarian'


def method(path, prefix):
    source = (ROOT / path).read_text()
    start = source.index(prefix)
    return source[start:source.index('\n}', start) + 2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--negative-control', action='store_true')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'table-drawing.inc').write_text(method('Sources/UI/NotesTableView.m', '- (void)drawRect:'))
    (OUT / 'delegate.inc').write_text(method('Sources/Browser/AppController.m', '- (void)tableView:(NSTableView *)aTableView willDisplayCell:'))
    table_source = (ROOT / 'Sources/UI/NotesTableView.m').read_text()
    start = table_source.index('\t\tloadStatusString =')
    end = table_source.index('\n\t\t', table_source.index('loadStatusStringWidth =', start))
    initialization = table_source[start:end]
    (OUT / 'status-init.inc').write_text(initialization)
    command = ['xcrun', 'clang', '-x', 'objective-c', '-include', 'Cocoa/Cocoa.h', '-include', 'Carbon/Carbon.h',
               '-Dforce_inline=__inline__', '-DCOMPILE_ASSERT(X,N)=_Static_assert(X,#N)', '-DIsLionOrLater=1',
               '-fno-objc-arc', '-Wno-incomplete-implementation', '-Wno-deprecated-declarations']
    for directory in sorted((ROOT / 'Sources').iterdir()):
        if directory.is_dir():
            command += ['-I', str(directory)]
    command += ['-I', str(OUT), str(HERE / 'probe.m'),
                'Sources/Utilities/NSString_CustomTruncation.m', 'Sources/Utilities/BufferUtils.c',
                'Sources/UI/ETOverlayScroller.m', 'Sources/UI/ETTransparentScroller.m',
                '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(OUT / 'probe')]
    subprocess.run(command, cwd=ROOT, check=True)
    result = subprocess.run([str(OUT / 'probe'), str(OUT), str(ROOT / 'Resources/Images')], cwd=ROOT,
                            text=True, capture_output=True, timeout=30)
    (OUT / 'output.txt').write_text(result.stdout + result.stderr)
    print(result.stdout + result.stderr, end='')
    result.check_returncode()
    if args.negative_control:
        obsolete = initialization.replace('[NSColor secondaryLabelColor]', '[NSColor colorWithCalibratedWhite:0 alpha:0.5]')
        assert obsolete != initialization
        try:
            (OUT / 'status-init.inc').write_text(obsolete)
            subprocess.run(command, cwd=ROOT, check=True)
            negative_output = OUT / 'negative-control'
            negative_output.mkdir(exist_ok=True)
            bad = subprocess.run([str(OUT / 'probe'), str(negative_output), str(ROOT / 'Resources/Images')], cwd=ROOT,
                                 text=True, capture_output=True, timeout=30)
            (OUT / 'negative-output.txt').write_text(bad.stdout + bad.stderr)
            assert bad.returncode != 0 and 'loading glyphs contrast' in bad.stderr, bad
            print('PASS: obsolete loading text color fails the native glyph assertion')
        finally:
            (OUT / 'status-init.inc').write_text(initialization)
            subprocess.run(command, cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
