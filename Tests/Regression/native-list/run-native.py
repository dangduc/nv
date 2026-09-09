#!/usr/bin/env python3
"""Render production preview attributes and tag images without launching nvALT."""
from pathlib import Path
import argparse
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
OUTPUT = ROOT / 'build' / 'NotesListAppearanceAudit'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--negative-control', action='store_true',
                        help='also require the obsolete SourceOut glyph compositing to fail')
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    source = (ROOT / 'Sources/Browser/LabelsListController.m').read_text()
    start = source.index('- (NSImage*)cachedLabelImageForWord:')
    end = source.index('\n}\n', start) + 3
    method = source[start:end]
    include = OUTPUT / 'label-method.inc'
    binary = OUTPUT / 'probe'
    command = ['xcrun', 'clang', '-x', 'objective-c', '-include', 'Cocoa/Cocoa.h',
               '-include', 'Carbon/Carbon.h', '-Dforce_inline=__inline__',
               '-DCOMPILE_ASSERT(X,N)=_Static_assert(X,#N)', '-fno-objc-arc',
               '-Wno-incomplete-implementation', '-Wno-deprecated-declarations']
    for directory in sorted((ROOT / 'Sources').iterdir()):
        if directory.is_dir():
            command += ['-I', str(directory)]
    command += ['-I', str(OUTPUT), str(HERE / 'probe.m'),
                'Sources/Utilities/NSString_CustomTruncation.m',
                'Sources/Utilities/NSBezierPath_NV.m',
                'Sources/Utilities/BufferUtils.c',
                '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(binary)]
    include.write_text(method)
    subprocess.run(command, cwd=ROOT, check=True)
    subprocess.run([str(binary), str(OUTPUT)], cwd=ROOT, check=True, timeout=30)
    if args.negative_control:
        old = 'NSCompositingOperationDestinationOut'
        assert method.count(old) == 1, 'Expected one production glyph compositing operation'
        include.write_text(method.replace(old, 'NSCompositeSourceOut'))
        negative_output = OUTPUT / 'source-out-mutation'
        negative_output.mkdir(exist_ok=True)
        try:
            subprocess.run(command, cwd=ROOT, check=True)
            result = subprocess.run([str(binary), str(negative_output)], cwd=ROOT,
                                    text=True, capture_output=True, timeout=30)
            (negative_output / 'output.txt').write_text(result.stdout + result.stderr)
            assert result.returncode != 0 and 'tag glyphs cut visible holes' in result.stderr, result
            print('PASS: SourceOut mutation fails the tag glyph-hole assertion')
        finally:
            include.write_text(method)
            subprocess.run(command, cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
