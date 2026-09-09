#!/usr/bin/env python3
"""Check hidden-window appearance delivery across native controller recreation."""
from pathlib import Path
import argparse
import os
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OUT = ROOT / 'build/NotesListAppearanceReview/round2/kingsbury'


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
    sources = {
        'setup.inc': browser[browser.index('- (void)setupBrowserContent'):browser.index('    const CGFloat headerHeight')] + '\n}\n',
        'view.inc': browser[browser.index('@interface NVBrowserContentView'):browser.index('@implementation AppController (BrowserUI)')],
        'controller.inc': method(browser, '- (void)browserAppearanceChanged') + '\n' + method(controller, '- (void)updateColorScheme'),
        'label.inc': method(labels, '- (NSImage*)cachedLabelImageForWord:'),
    }
    command = ['xcrun', 'clang', '-arch', 'arm64', '-x', 'objective-c', '-include', 'Cocoa/Cocoa.h',
               '-fno-objc-arc', '-Wno-incomplete-implementation', '-Wno-deprecated-declarations',
               '-I', str(ROOT / 'Sources/Preferences'), '-I', str(ROOT / 'Sources/Utilities'),
               '-I', str(OUT), str(HERE / 'probe.m'), 'Sources/Utilities/NSBezierPath_NV.m',
               '-framework', 'Cocoa', '-o', str(OUT / 'probe')]

    def run(name, replacements=(), zombie=False):
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
        environment = dict(os.environ)
        if zombie:
            environment['NSZombieEnabled'] = 'YES'
        result = subprocess.run([str(OUT / 'probe')], cwd=ROOT, capture_output=True, text=True,
                                env=environment, timeout=45)
        (OUT / f'{name}.log').write_text(result.stdout + result.stderr)
        return result

    for name, zombie in [('production', False), ('zombies', True)]:
        result = run(name, zombie=zombie)
        print(result.stdout + result.stderr, end='')
        result.check_returncode()
        assert 'message sent to deallocated instance' not in result.stderr
    if args.negative_controls:
        mutations = [
            ('dropped-callback', [('[[[self window] windowController] browserAppearanceChanged];', '(void)self;')],
             'hidden application appearance reaches its controller automatically'),
            ('pinned-list', [('[notesSubview setTranslatesAutoresizingMaskIntoConstraints:NO];',
                              '[notesSubview setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];\n[notesSubview setTranslatesAutoresizingMaskIntoConstraints:NO];')],
             'hidden list inherits the application appearance'),
            ('stale-tag-key', [('NSArray *imgKey = @[[aWord lowercaseString], @(isHighlighted), fillColor];',
                               'NSArray *imgKey = @[[aWord lowercaseString], @(isHighlighted)];')],
             'retained cache gives different colors different images'),
        ]
        try:
            for name, replacements, expected in mutations:
                result = run(name, replacements)
                assert result.returncode != 0 and expected in result.stderr, (name, result.stdout, result.stderr)
                print(f'PASS: {name} mutation rejected')
        finally:
            for filename, source in sources.items():
                (OUT / filename).write_text(source)
            subprocess.run(command, cwd=ROOT, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == '__main__':
    main()
