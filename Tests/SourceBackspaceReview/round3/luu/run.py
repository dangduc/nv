#!/usr/bin/env python3
"""Inventory cost-relevant source operations. This never compiles or runs nvALT."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = '54ce3b8f94c382e8a4c20c871b8fb20dc30cc376'
PRODUCTION = ['Sources/Browser/AppController.m', 'Sources/Browser/AppController_Search.m',
              'Sources/Editor/LinkingEditor.h', 'Sources/Editor/LinkingEditor.m']
CONTEXT = ['Sources/Search/NVSearchQuery.h', 'Sources/Search/NVSearchService.m']

def hashes(paths):
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in paths}

def method(source, signature):
    start = source.index(signature)
    return source[start:source.index('\n}', start) + 2]

def revision_file(revision, name):
    return subprocess.check_output(['git', 'show', revision + ':' + name], cwd=ROOT, text=True)

before = hashes(PRODUCTION)
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
editor = (ROOT / PRODUCTION[3]).read_text()
search = (ROOT / PRODUCTION[1]).read_text()
browser = (ROOT / PRODUCTION[0]).read_text()
old_editor = revision_file(BASE, PRODUCTION[3])
draw = method(editor, '- (NSDictionary *)layoutManager:')
old_draw = method(old_editor, '- (NSDictionary *)layoutManager:')
invalidate = method(editor, '- (void)invalidateSearchHighlights')
clear = method(editor, '- (void)removeHighlightedTerms')
install = method(editor, '- (void)setSearchHighlightRanges:')
old_install = method(old_editor, '- (void)setSearchHighlightRanges:')
observe = method(search, '- (void)searchSourceStorageWillProcessEditing:')
refresh = method(search, '- (void)refreshSearchHighlights')
changed = method(browser, '- (void)textDidChange:')
query_header = (ROOT / CONTEXT[0]).read_text()
service = (ROOT / CONTEXT[1]).read_text()
checks = []
def check(condition, description):
    if not condition:
        raise SystemExit('Source inventory no longer applies: ' + description)
    checks.append(description)

new_prefix = draw[:draw.index('    if (!screen')]
old_tail = old_draw[old_draw.index('    if (!screen'):]
new_tail = draw[draw.index('    if (!screen'):]
check(old_tail == new_tail, 'All drawing logic after the new suppression branch is unchanged from the base')
check(new_prefix.count('[attributes mutableCopy]') == 1 and
      'if (searchHighlightsInvalidated && [attributes objectForKey:NSBackgroundColorAttributeName])' in new_prefix,
      'The added mutable copy has one site, conditional on pending invalidation and an input background')
check(old_draw.count('[NSMutableDictionary dictionaryWithDictionary:') == 1 and
      draw.count('[NSMutableDictionary dictionaryWithDictionary:') == 1,
      'The existing valid screen-drawing path retains its one dictionary-construction site')
check(invalidate.index('if (searchHighlightsInvalidated) return;') < invalidate.index('performSelector:'),
      'The pending flag prevents repeat invalidation from scheduling another callback')
check(invalidate.count('performSelector:') == 1 and 'afterDelay:0 inModes:@[NSRunLoopCommonModes]' in invalidate,
      'Initial invalidation contains one zero-delay callback site in common modes')
check(clear.index('cancelPreviousPerformRequestsWithTarget:') < clear.index('if ([[self textStorage] editedMask]'),
      'Every clear cancels the old request before the retry decision')
check(clear.count('performSelector:') == 1 and 'afterDelay:0.01 inModes:@[NSRunLoopCommonModes]' in clear,
      'The character-edit guard contains one 10 ms retry site')
check(clear.count('removeTemporaryAttribute:') == 1 and 'NSMakeRange(0, [[self string] length])' in clear,
      'A stable clear retains one native removal operation over the current source length')
check('if (storage != [textView textStorage] || !([storage editedMask] & NSTextStorageEditedCharacters)) return;' in observe,
      'Attribute-only storage notifications return before generation advance and callback scheduling')
check(observe.index('++searchHighlightGeneration;') < observe.index('[textView invalidateSearchHighlights]'),
      'Character notifications advance the generation before deferred cleanup')
check('[textView removeHighlightedTerms];' in changed,
      'The ordinary text-change callback also clears highlights and can cancel the pending request')
check(install.index('[self removeHighlightedTerms];') < install.index('if (searchHighlightsInvalidated) return;') < install.index('for (NSValue *value in ranges)'),
      'Fresh publication clears old state before its range loop and stops if clearing remains deferred')
check('if (displayed++ == NVSearchMaximumDisplayedRanges) break;' in install and
      'if (displayed++ == NVSearchMaximumDisplayedRanges) break;' in old_install,
      'The range-publication cap is unchanged from the base')
maximum_ranges = int(re.search(r'NVSearchMaximumDisplayedRanges\s*=\s*(\d+)', query_header).group(1))
check(maximum_ranges == 2048, 'The source defines a 2048-range display limit')
check('[textView removeHighlightedTerms];' in refresh and '[textView setSearchHighlightRanges:ranges]' in refresh,
      'Async refresh contains an initial clear and a later guarded publication')
check('dispatch_async(_worker' in service and 'maximumCount:NVSearchMaximumDisplayedRanges' in service,
      'The range service places bounded literal discovery on its worker queue')

# Inventory ordinary call sites and their enclosing Objective-C method signature.
# This is a lexical source inventory, not a complete Objective-C call graph.
calls = []
pattern = re.compile(r'\[(?:self|textView)\s+(removeHighlightedTerms|invalidateSearchHighlights|setSearchHighlightRanges:)')
for name in PRODUCTION:
    if not name.endswith('.m'):
        continue
    current = None
    for line_number, line in enumerate((ROOT / name).read_text().splitlines(), 1):
        if re.match(r'^[-+]\s*\(', line):
            current = line.strip()
        if pattern.search(line):
            calls.append({'path': name, 'line': line_number, 'enclosing_signature': current, 'source': line.strip()})

inventory = {
    'scope': 'Static source operations and conditional bounds only. No runtime workload, AppKit call, timing, or GUI.',
    'checks': len(checks), 'source_checks': checks, 'ordinary_call_sites': calls,
    'drawing': {'new_mutable_copy_sites': 1, 'added_copies_per_stable_draw_call': 0,
                'added_copies_per_pending_draw_call_with_background': 1,
                'existing_screen_result_dictionary_sites_before': 1,
                'existing_screen_result_dictionary_sites_after': 1},
    'scheduling': {'initial_delay_seconds': 0, 'guard_retry_delay_seconds': 0.01,
                   'initial_callback_sites': 1, 'guard_retry_sites': 1,
                   'stable_clear_scheduling_sites': 0,
                   'conditional_pending_request_bound_by_editors': [{'editors': n, 'pending_requests_at_most': n} for n in (1, 4, 16)],
                   'bound_assumptions': 'Main-thread calls, normal NSObject cancellation semantics, and one invalidation flag per editor. This is not a measured callback count.'},
    'display_range_limit': maximum_ranges,
    'whole_source_clear_operation_sites': 1,
}
after = hashes(PRODUCTION)
check(before == after, 'The four production source hashes remain unchanged')
inventory['checks'] = len(checks)
inventory['source_checks'] = checks
manifest = {'base': BASE, 'reviewed_head': head, 'production_sha256_before': before,
            'production_sha256_after': after, 'context_sha256': hashes(CONTEXT),
            'scope': inventory['scope']}
(HERE / 'inventory.json').write_text(json.dumps(inventory, indent=2) + '\n')
(HERE / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
output = '\n'.join('PASS: ' + value for value in checks) + '\n'
output += json.dumps(inventory, indent=2) + '\n'
(HERE / 'output.txt').write_text(output)
print(output, end='')
