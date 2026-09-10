#!/usr/bin/env python3
"""Read-only production diff inventory; writes evidence only beside this script."""
import difflib
import hashlib
import json
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = '54ce3b8f94c382e8a4c20c871b8fb20dc30cc376'
FILES = ['Sources/Browser/AppController.m', 'Sources/Browser/AppController_Search.m',
         'Sources/Editor/LinkingEditor.h', 'Sources/Editor/LinkingEditor.m']

def git(*arguments):
    return subprocess.check_output(['git', *arguments], cwd=ROOT, text=True)

def hashes():
    return {path: hashlib.sha256((ROOT/path).read_bytes()).hexdigest() for path in FILES}

def method(source, prefix):
    start = source.index(prefix)
    return source[start:source.index('\n}', start)+2]

def normalize(text):
    return '\n'.join(line.strip() for line in text.splitlines())

def context(source, index, header):
    if header:
        return 'header declaration/state'
    candidates = [match for match in re.finditer(r'^[-+]\s*\([^)]+\).*', source, re.MULTILINE)
                  if source.count('\n', 0, match.start()) <= index]
    if not candidates:
        return 'file scope'
    start = candidates[-1].start()
    signature = source[start:source.index('{', start)].strip()
    return ' '.join(signature.split())

start_head = git('rev-parse', 'HEAD').strip()
before = hashes()
original = {path: git('show', BASE+':'+path) for path in FILES}
current = {path: (ROOT/path).read_text() for path in FILES}
checks = []

def check(value, description):
    checks.append({'passed': bool(value), 'description': description})
    if not value:
        raise AssertionError(description)

inventory = []
for path in FILES:
    old_lines = original[path].splitlines()
    new_lines = current[path].splitlines()
    matcher = difflib.SequenceMatcher(a=old_lines, b=new_lines, autojunk=False)
    for operation, old_start, old_end, new_start, new_end in matcher.get_opcodes():
        if operation == 'equal':
            continue
        for side, lines, source, first, last in [('-', old_lines, original[path], old_start, old_end),
                                                ('+', new_lines, current[path], new_start, new_end)]:
            for index in range(first, last):
                text = lines[index]
                stripped = text.strip()
                kind = ('blank' if not stripped else 'comment-only' if stripped.startswith('//')
                        else 'structural' if stripped in ('{', '}') else 'declaration' if path.endswith('.h')
                        or stripped.startswith('- (') or stripped.startswith('+ (') else 'code')
                inventory.append({'side': side, 'path': path, 'line': index+1, 'kind': kind,
                                  'method': context(source, index, path.endswith('.h')), 'text': text})

header = current[FILES[2]]
editor = current[FILES[3]]
old_editor = original[FILES[3]]
observer = method(current[FILES[1]], '- (void)searchSourceStorageWillProcessEditing:')
old_observer = method(original[FILES[1]], '- (void)searchSourceStorageWillProcessEditing:')
new_invalidation = method(editor, '- (void)invalidateSearchHighlights')
cleanup = method(editor, '- (void)removeHighlightedTerms')
old_cleanup = method(old_editor, '- (void)removeHighlightedTerms')
setter = method(editor, '- (void)setSearchHighlightRanges:')
old_setter = method(old_editor, '- (void)setSearchHighlightRanges:')
render = method(editor, '- (NSDictionary *)layoutManager:(NSLayoutManager *)manager shouldUseTemporaryAttributes:')
old_render = method(old_editor, '- (NSDictionary *)layoutManager:(NSLayoutManager *)manager shouldUseTemporaryAttributes:')
render_prefix = '''    if (searchHighlightsInvalidated && [attributes objectForKey:NSBackgroundColorAttributeName]) {
        NSMutableDictionary *display = [[attributes mutableCopy] autorelease];
        [display removeObjectForKey:NSBackgroundColorAttributeName];
        attributes = display;
    }
'''
check(header.count('- (void)invalidateSearchHighlights;') == 1 and
      editor.count('- (void)invalidateSearchHighlights {') == 1,
      'New no-argument invalidation selector has one declaration and one definition.')
check(header.count('- (void)removeHighlightedTerms;') == 1 and
      editor.count('- (void)removeHighlightedTerms {') == 1,
      'Cleanup selector retains one declaration and one definition.')
check(header.count('BOOL searchHighlightsInvalidated;') == 1,
      'Pending state has one editor instance-variable declaration.')
check(observer == old_observer.replace('[textView removeHighlightedTerms];', '[textView invalidateSearchHighlights];'),
      'Storage observer changes only the cleanup call; storage identity, character mask, and generation fence remain unchanged.')
check(setter.replace('    if (searchHighlightsInvalidated) return;\n', '') == old_setter,
      'Range setter retains its exact old body after removal of the new pending-state guard.')
check('range.location <= length && range.length <= length - range.location && range.length' in setter,
      'Range setter retains subtraction-based bounds checks and rejects zero-length ranges.')
check('if (displayed++ == NVSearchMaximumDisplayedRanges) break;' in setter,
      'Range setter retains the independent displayed-range cap.')
check(normalize(old_cleanup.split('\n')[1]) == normalize(cleanup.split('\n')[-2]),
      'Cleanup retains the same background removal over the current string length.')
check('if ([[self textStorage] editedMask] & NSTextStorageEditedCharacters)' in cleanup and
      cleanup.index('editedMask') < cleanup.index('searchHighlightsInvalidated = NO;') < cleanup.index('removeTemporaryAttribute:'),
      'Character-edit guard precedes pending-state reset and temporary-attribute removal.')
check('afterDelay:0.01 inModes:@[NSRunLoopCommonModes]' in cleanup and
      cleanup.index('afterDelay:0.01') < cleanup.index('        return;'),
      'Dirty-storage branch schedules a 10 ms common-mode retry and returns before layout mutation.')
check('if (searchHighlightsInvalidated) return;' in new_invalidation and
      new_invalidation.index('if (searchHighlightsInvalidated) return;') < new_invalidation.index('performSelector:'),
      'Initial invalidation coalesces pending work before scheduling cleanup.')
check('layoutManager' not in new_invalidation and 'removeTemporaryAttribute' not in new_invalidation,
      'Initial invalidation contains no layout-manager or temporary-attribute operation.')
check(render.replace(render_prefix, '') == old_render,
      'Drawing delegate retains its exact previous body after removal of the new background-only prefix.')
check('[display removeObjectForKey:NSBackgroundColorAttributeName];' in render_prefix and
      'NSForegroundColorAttributeName' not in render_prefix,
      'Added drawing prefix removes only the background key from a mutable copy.')
for prefix in ['- (void)highlightRangesTemporarily:', '- (NSRange)highlightTermsTemporarilyReturningFirstRange:',
               '- (NSColor *)sourceColorForCapture:', '- (NSDictionary *)currentSearchHighlightAttributes']:
    check(method(editor, prefix) == method(old_editor, prefix), prefix+' remains byte-identical to the base.')
check(method(current[FILES[1]], '- (void)refreshSearchHighlights') ==
      method(original[FILES[1]], '- (void)refreshSearchHighlights'),
      'Asynchronous highlight refresh remains byte-identical to the base.')
attachment = method(current[FILES[0]], '- (void)_setCurrentNote:(NoteObject *)aNote finishingEditing:')
old_attachment = method(original[FILES[0]], '- (void)_setCurrentNote:(NoteObject *)aNote finishingEditing:')
attachment_addition = "    // Cancel the old note's deferred cleanup before this editor changes storage.\n    [textView removeHighlightedTerms];\n"
check(attachment.replace(attachment_addition, '') == old_attachment and
      attachment.index('[textView removeHighlightedTerms]') < attachment.index('removeLayoutManager:layout'),
      'Note attachment changes only by clearing the old editor before detaching its layout manager.')
check('[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(removeHighlightedTerms) object:nil];' in
      method(editor, '- (void)dealloc'),
      'Editor deallocation cancels the same cleanup selector that invalidation schedules.')
check(sum(item['kind'] == 'code' and item['side'] == '-' for item in inventory) == 2,
      'Only two old executable lines are replaced: the observer call and the reindented cleanup operation.')
after = hashes()
check(before == after, 'All four production hashes remain unchanged during this source-only review.')
changed_methods = sorted({item['method'] for item in inventory if not item['path'].endswith('.h') and item['kind'] != 'blank'})
counts = {side: {kind: sum(item['side'] == side and item['kind'] == kind for item in inventory)
                 for kind in ['code', 'declaration', 'structural', 'comment-only', 'blank']} for side in ['+', '-']}
manifest = {'base': BASE, 'head_start': start_head, 'head_end': git('rev-parse', 'HEAD').strip(),
            'last_production_commit': git('log', '-1', '--format=%H', '--', *FILES).strip(),
            'production_sha256_before': before, 'production_sha256_after': after,
            'unchanged': before == after, 'checks': checks, 'changed_methods': changed_methods,
            'line_counts': counts, 'changed_lines': inventory,
            'scope': 'Static source comparisons only. No compilation, app launch, TextKit operation, crash reproduction, or defective variant.'}
(HERE/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
(HERE/'production.diff').write_text(git('diff', BASE, '--', *FILES))
lines = ['STATIC REVIEW ONLY', 'HEAD: '+start_head, 'Production: '+manifest['last_production_commit'],
         'Changed methods: '+str(len(changed_methods)), *['  '+name for name in changed_methods],
         'Changed line counts: '+json.dumps(counts), '', 'ALL ADDED AND REMOVED LINES']
for item in inventory:
    lines.append(f"{item['side']} {item['path']}:{item['line']} [{item['kind']}] {item['text']}")
lines += ['', 'SOURCE COMPARISON CHECKS', *['PASS: '+item['description'] for item in checks],
          f'STATIC CHECKS PASSED: {len(checks)}', 'No runtime result is claimed.']
(HERE/'output.txt').write_text('\n'.join(lines)+'\n')
print('\n'.join(lines))
