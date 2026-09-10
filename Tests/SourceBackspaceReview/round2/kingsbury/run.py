#!/usr/bin/env python3
"""Adversarial native schedules around exact highlight cleanup/publication methods."""
import hashlib
import json
import platform
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
FILES = ['Sources/Editor/LinkingEditor.h', 'Sources/Editor/LinkingEditor.m',
         'Sources/Browser/AppController_Search.m', 'Sources/Browser/AppController.m']

def hashes():
    return {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in FILES}

def method(path, name):
    source = (ROOT / path).read_text()
    start = source.index(name)
    return source[start:source.index('\n}', start) + 2]

start = hashes()
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
editor = FILES[1]
originals = {
    'editor.inc': '\n'.join(method(editor, name) for name in [
        '- (void)invalidateSearchHighlights', '- (void)removeHighlightedTerms', '- (void)setSearchHighlightRanges:']),
    'observer.inc': method(FILES[2], '- (void)searchSourceStorageWillProcessEditing:'),
    'refresh.inc': method(FILES[2], '- (void)refreshSearchHighlights'),
}
for name, text in originals.items():
    (HERE / name).write_text(text + '\n')
mutants = [
    ('missing-edit-fence', 'observer.inc', '    ++searchHighlightGeneration;\n', ''),
    ('missing-refresh-fence', 'refresh.inc', 'NSUInteger generation = ++searchHighlightGeneration;', 'NSUInteger generation = searchHighlightGeneration;'),
    ('missing-selection-fence', 'refresh.inc', '[[session rowKeyAtIndex:[notesTableView primarySelectedRow]] isEqual:key]', 'YES'),
    ('missing-current-results-fence', 'refresh.inc', 'generation == searchHighlightGeneration && [session searchResultsAreCurrent] &&', 'generation == searchHighlightGeneration &&'),
    ('unsafe-dirty-cleanup', 'editor.inc', 'if ([[self textStorage] editedMask] & NSTextStorageEditedCharacters)', 'if (NO)'),
    ('unsafe-dirty-publication', 'editor.inc', '    if (searchHighlightsInvalidated) return;\n    NSColor *color', '    NSColor *color'),
]
results = {}
try:
    for label, filename, old, new in [('positive', None, None, None)] + mutants:
        for name, text in originals.items():
            (HERE / name).write_text(text + '\n')
        if filename:
            assert old in originals[filename], label
            (HERE / filename).write_text(originals[filename].replace(old, new) + '\n')
        binary = ROOT / 'build' / ('BackspaceReview-r2-kingsbury-' + label)
        build = subprocess.run(['xcrun', 'clang', '-fno-objc-arc', '-fblocks', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter', '-Wno-unused-variable', '-g', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', str(HERE/'probe.m'), '-framework', 'Cocoa', '-o', str(binary)], capture_output=True, text=True)
        if build.returncode:
            raise RuntimeError(build.stdout + build.stderr)
        result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
        (HERE / (label + '.txt')).write_text(result.stdout + result.stderr)
        results[label] = {'exit': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}
        if label == 'positive':
            assert result.returncode == 0, result.stdout + result.stderr
        else:
            assert result.returncode != 0 and 'FAIL:' in result.stderr, f'{label} did not fail an assertion: {result}'
        print(label + ': ' + (result.stdout + result.stderr).strip())
finally:
    for name, text in originals.items():
        (HERE / name).write_text(text + '\n')
    end = hashes()
    (HERE/'manifest.json').write_text(json.dumps({'head': head, 'platform': platform.platform(), 'source_hashes_start': start, 'source_hashes_end': end, 'production_unchanged': start == end, 'results': results}, indent=2) + '\n')
assert start == end, 'Production changed during review'
