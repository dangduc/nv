#!/usr/bin/env python3
"""Run isolated native window/appearance transition checks against production methods."""
from pathlib import Path
import argparse
import subprocess

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build/NotesListAppearanceReview/round1/kingsbury'


def method(source, signature):
    start = source.index(signature)
    end = source.index('\n}', start) + 2
    return source[start:end]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--negative-controls', action='store_true')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    browser = (ROOT / 'Sources/Browser/AppController_BrowserUI.m').read_text()
    controller = (ROOT / 'Sources/Browser/AppController.m').read_text()
    labels = (ROOT / 'Sources/Browser/LabelsListController.m').read_text()
    editor = (ROOT / 'Sources/Editor/LinkingEditor.m').read_text()
    setup = browser[browser.index('- (void)setupBrowserContent'):browser.index('    const CGFloat headerHeight')]
    # Use the unmodified list construction prefix. The fixture supplies its own editor.
    setup += '\n}\n'
    source = {
        'setup.inc': setup,
        'appearance-view.inc': browser[browser.index('@interface NVBrowserContentView'):browser.index('@implementation AppController (BrowserUI)')],
        'controller.inc': '\n'.join(method(browser, signature) for signature in [
            '- (CGFloat)notesListHeight', '- (void)setNotesListHeight:',
            '- (void)updateNotesListVisibility', '- (void)browserAppearanceChanged']) + '\n' + method(controller, '- (void)updateColorScheme'),
        'label.inc': method(labels, '- (NSImage*)cachedLabelImageForWord:'),
        'editor.inc': method(editor, '- (void)updateTextColors'),
    }
    command = ['xcrun', 'clang', '-arch', 'arm64', '-x', 'objective-c', '-include', 'Cocoa/Cocoa.h',
               '-include', 'Carbon/Carbon.h', '-Dforce_inline=__inline__',
               '-DCOMPILE_ASSERT(X,N)=_Static_assert(X,#N)', '-fno-objc-arc',
               '-Wno-incomplete-implementation', '-Wno-deprecated-declarations']
    for directory in sorted((ROOT / 'Sources').iterdir()):
        if directory.is_dir():
            command += ['-I', str(directory)]
    command += ['-I', str(OUT), str(HERE / 'probe.m'),
                'Sources/Utilities/NSString_CustomTruncation.m',
                'Sources/Utilities/NSBezierPath_NV.m', 'Sources/Utilities/BufferUtils.c',
                '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(OUT / 'probe')]

    def run(name, replacements=None):
        for filename, content in source.items():
            if replacements:
                for old, new in replacements:
                    content = content.replace(old, new)
            (OUT / filename).write_text(content)
        build = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        (OUT / f'{name}-compile.log').write_text(build.stdout + build.stderr)
        build.check_returncode()
        result = subprocess.run([str(OUT / 'probe')], cwd=ROOT, capture_output=True, text=True, timeout=45)
        (OUT / f'{name}.log').write_text(result.stdout + result.stderr)
        return result

    result = run('production')
    print(result.stdout, end='')
    if result.returncode:
        print(result.stderr, end='')
        result.check_returncode()
    if args.negative_controls:
        mutations = [
            ('dropped-callback', [('[[[self window] windowController] browserAppearanceChanged];', '(void)self;')], 'native view callback reaches the owning controller'),
            ('white-background', [('[notesTableView setBackgroundColor:[NSColor textBackgroundColor]]', '[notesTableView setBackgroundColor:[NSColor whiteColor]]')], 'list background matches its own appearance'),
            ('shared-tag-key', [('NSArray *imgKey = @[[aWord lowercaseString], @(isHighlighted), fillColor];', 'NSArray *imgKey = @[[aWord lowercaseString], @(isHighlighted)];')], 'tag image follows its own appearance'),
            ('pinned-list', [('[notesSubview setTranslatesAutoresizingMaskIntoConstraints:NO];', '[notesSubview setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];\n[notesSubview setTranslatesAutoresizingMaskIntoConstraints:NO];')], 'list inherits its own window appearance'),
        ]
        try:
            for name, replacements, failure in mutations:
                changed = run(name, replacements)
                assert changed.returncode != 0 and failure in changed.stderr, (name, changed.stdout, changed.stderr)
                print(f'PASS: {name} negative control rejects the regression')
        finally:
            for filename, content in source.items():
                (OUT / filename).write_text(content)
            subprocess.run(command, cwd=ROOT, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == '__main__':
    main()
