#!/usr/bin/env python3
"""Challenge each stateful part of the fix with separate native AppKit processes."""
from pathlib import Path
import hashlib
import json
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OUT = ROOT / 'build/BackspaceReview/round1/contrarian-a'
OUT.mkdir(parents=True, exist_ok=True)
FILES = ['Sources/Browser/AppController.m', 'Sources/Browser/AppController_Search.m',
         'Sources/Editor/LinkingEditor.h', 'Sources/Editor/LinkingEditor.m']

def hashes():
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in FILES}

def method(source, name):
    start = source.index(name)
    return source[start:source.index('\n}', start) + 2]

before = hashes()
base = '54ce3b8f94c382e8a4c20c871b8fb20dc30cc376'
reviewed_head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
editor_source = (ROOT / FILES[3]).read_text()
observer = method((ROOT / FILES[1]).read_text(), '- (void)searchSourceStorageWillProcessEditing:')
names = ['- (NSColor *)sourceColorForCapture:', '- (NSDictionary *)layoutManager:',
         '- (void)invalidateSearchHighlights', '- (void)removeHighlightedTerms',
         '- (void)setSearchHighlightRanges:']
editor = '\n'.join(method(editor_source, name) for name in names)
template = (HERE / 'probe.m.in').read_text()
old_editor = subprocess.check_output(['git', 'show', base + ':' + FILES[3]], cwd=ROOT, text=True)
old_observer = method(subprocess.check_output(['git', 'show', base + ':' + FILES[1]], cwd=ROOT, text=True), '- (void)searchSourceStorageWillProcessEditing:')
variants = {
    'production': (editor, observer, 'production'),
    'no_suppression': (editor.replace('if (searchHighlightsInvalidated && [attributes objectForKey:NSBackgroundColorAttributeName])', 'if (NO)'), observer, 'suppression'),
    'no_cancel': (editor.replace('    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(removeHighlightedTerms) object:nil];\n', ''), observer, 'cancel'),
    'no_edit_guard': (editor.replace('if ([[self textStorage] editedMask] & NSTextStorageEditedCharacters)', 'if (NO)'), observer, 'guard'),
    'no_generation': (editor, observer.replace('++searchHighlightGeneration;', '(void)searchHighlightGeneration;'), 'generation'),
    # This variant changes only the controller's pre-detach call in the fixture.
    'no_switch_clear': (editor, observer, 'switch'),
    # Restore both affected old methods to distinguish the layout phase from
    # character deletion alone. This process has no cached view glyph rectangle.
    'original_uncached_layout': (editor.replace(method(editor_source, '- (void)removeHighlightedTerms'), method(old_editor, '- (void)removeHighlightedTerms')), old_observer, 'causal'),
}
expected_failures = {
    'no_suppression': 'pending cleanup cannot display the old search background',
    'no_cancel': 'queued old cleanup cannot erase a newly published result',
    'no_edit_guard': 'explicit clear respects the native character-edit transaction',
    'no_generation': 'old async generation is invalidated before a run-loop turn',
    'no_switch_clear': 'old note callback does not mutate the replacement storage',
}
rows = []
for name, (e, o, scenario) in variants.items():
    if name not in ('production', 'no_switch_clear'):
        assert (e, o) != (editor, observer), name
    source = OUT / (name + '.m')
    source.write_text(template.replace('/* EDITOR_METHODS */', e).replace('/* OBSERVER_METHOD */', o))
    binary = OUT / name
    subprocess.run(['xcrun', 'clang', '-O1', '-g', '-fno-objc-arc', '-fblocks',
                    '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter',
                    str(source), '-framework', 'Cocoa', '-o', str(binary)], check=True)
    result = subprocess.run([str(binary), scenario], capture_output=True, text=True, timeout=20)
    (OUT / (name + '.log')).write_text(result.stdout + result.stderr)
    passed = result.returncode == 0
    should_pass = name in ('production', 'original_uncached_layout')
    if should_pass and not passed:
        raise SystemExit(result.stdout + result.stderr)
    if not should_pass and passed:
        raise SystemExit('Simplification unexpectedly survived: ' + name)
    if not should_pass and (result.returncode != 1 or 'FAIL: ' + expected_failures[name] not in result.stderr):
        raise SystemExit('Unrelated control failure: ' + name + '\n' + result.stdout + result.stderr)
    rows.append({'variant': name, 'returncode': result.returncode,
                 'stdout': result.stdout, 'stderr': result.stderr})
    print(name + ': ' + ('PASS' if passed else 'REJECTED') + '\n' + result.stdout + result.stderr)

after = hashes()
assert before == after, 'Production changed during review'
manifest = {'base': base, 'reviewed_head': reviewed_head,
            'production_sha256_before': before, 'production_sha256_after': after,
            'platform': subprocess.check_output(['sw_vers'], text=True),
            'results': rows,
            'scope': 'Exact production editor and observer methods; native NSTextStorage/NSLayoutManager; no window or bitmap drawing.'}
(HERE / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
(HERE / 'output.txt').write_text('\n'.join(row['variant'] + '\n' + row['stdout'] + row['stderr'] for row in rows))
