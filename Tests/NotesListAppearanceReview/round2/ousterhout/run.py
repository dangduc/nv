#!/usr/bin/env python3
"""Check automatic native appearance delivery and draw-time cache ownership."""
from pathlib import Path
import argparse
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OUT = ROOT / 'build/NotesListAppearanceReview/round2/ousterhout'


def method(source, signature):
    start = source.index(signature)
    return source[start:source.index('\n}', start) + 2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--negative-controls', action='store_true')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    browser = (ROOT / 'Sources/Browser/AppController_BrowserUI.m').read_text()
    controller = (ROOT / 'Sources/Browser/AppController.m').read_text()
    labels = (ROOT / 'Sources/Browser/LabelsListController.m').read_text()
    note = (ROOT / 'Sources/Model/NoteObject.m').read_text()
    sources = {
        'setup.inc': browser[browser.index('- (void)setupBrowserContent'):browser.index('    const CGFloat headerHeight')] + '\n}\n',
        'appearance-view.inc': browser[browser.index('@interface NVBrowserContentView'):browser.index('@implementation AppController (BrowserUI)')],
        'controller.inc': method(browser, '- (void)browserAppearanceChanged') + '\n' + method(controller, '- (void)updateColorScheme'),
        'labels.inc': method(labels, '- (NSImage*)cachedLabelImageForWord:'),
        'note-drawing.inc': '\n'.join(method(note, signature) for signature in [
            '- (NSSize)sizeOfLabelBlocks', '- (void)drawLabelBlocksInRect:', '- (void)_drawLabelBlocksInRect:']),
    }
    command = ['xcrun', 'clang', '-arch', 'arm64', '-x', 'objective-c', '-include', 'Cocoa/Cocoa.h',
               '-include', 'Carbon/Carbon.h', '-Dforce_inline=__inline__',
               '-DCOMPILE_ASSERT(X,N)=_Static_assert(X,#N)', '-fno-objc-arc',
               '-Wno-incomplete-implementation', '-Wno-deprecated-declarations']
    for directory in sorted((ROOT / 'Sources').iterdir()):
        if directory.is_dir():
            command += ['-I', str(directory)]
    command += ['-I', str(OUT), str(HERE / 'probe.m'),
                'Sources/Utilities/NSString_CustomTruncation.m', 'Sources/Utilities/NSBezierPath_NV.m',
                'Sources/Utilities/BufferUtils.c', '-framework', 'Cocoa', '-framework', 'Carbon',
                '-o', str(OUT / 'probe')]

    def run(name, replacements=()):
        for filename, original in sources.items():
            content = original
            for old, new in replacements:
                content = content.replace(old, new)
            (OUT / filename).write_text(content)
        build = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        (OUT / f'{name}-compile.log').write_text(build.stdout + build.stderr)
        if build.returncode:
            print(build.stdout + build.stderr, end='')
            build.check_returncode()
        result = subprocess.run([str(OUT / 'probe'), str(OUT)], cwd=ROOT, capture_output=True, text=True, timeout=45)
        (OUT / f'{name}.log').write_text(result.stdout + result.stderr)
        return result

    result = run('production')
    print(result.stdout + result.stderr, end='')
    result.check_returncode()
    if args.negative_controls:
        mutations = [
            ('dropped-delivery', [('[[[self window] windowController] browserAppearanceChanged];', '(void)self;')],
             'automatic native appearance callback reaches the owner'),
            ('pinned-list', [('[notesSubview setTranslatesAutoresizingMaskIntoConstraints:NO];',
                              '[notesSubview setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];\n[notesSubview setTranslatesAutoresizingMaskIntoConstraints:NO];')],
             'attached list inherits the destination appearance'),
            ('measurement-color-leak', [('NSArray *imgKey = @[[aWord lowercaseString], @(isHighlighted), fillColor];',
                                        'NSArray *imgKey = @[[aWord lowercaseString], @(isHighlighted)];')],
             'native tag draw uses its destination color after a foreign measurement'),
        ]
        try:
            for name, replacements, expected in mutations:
                negative = run(name, replacements)
                assert negative.returncode != 0 and expected in negative.stderr, (name, negative.stdout, negative.stderr)
                print(f'PASS: {name} mutation rejected')
        finally:
            for filename, content in sources.items():
                (OUT / filename).write_text(content)
            subprocess.run(command, cwd=ROOT, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == '__main__':
    main()
