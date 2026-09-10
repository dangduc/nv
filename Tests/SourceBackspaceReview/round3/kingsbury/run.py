#!/usr/bin/env python3
"""Inventory state transitions and compare them with saved earlier evidence."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
FILES = ['Sources/Browser/AppController.m', 'Sources/Browser/AppController_Search.m',
         'Sources/Editor/LinkingEditor.h', 'Sources/Editor/LinkingEditor.m']

def hashes():
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in FILES}

def method(source, signature):
    start = source.index(signature)
    return source[start:source.index('\n}', start) + 2]

before = hashes()
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
sources = {name: (ROOT / name).read_text() for name in FILES}
browser, search, header, editor = (sources[name] for name in FILES)
refresh = method(search, '- (void)refreshSearchHighlights')
observer = method(search, '- (void)searchSourceStorageWillProcessEditing:')
switch = method(browser, '- (void)_setCurrentNote:(NoteObject *)aNote finishingEditing:')
clear = method(editor, '- (void)removeHighlightedTerms')
invalidate = method(editor, '- (void)invalidateSearchHighlights')
publish = method(editor, '- (void)setSearchHighlightRanges:')
draw = method(editor, '- (NSDictionary *)layoutManager:')
checks = []
def check(value, description):
    if not value:
        raise SystemExit('State inventory no longer applies: ' + description)
    checks.append(description)

categories = {
    'generation_updates': re.compile(r'(?:\+\+searchHighlightGeneration|searchHighlightGeneration\+\+)'),
    'generation_reads': re.compile(r'generation == searchHighlightGeneration'),
    'observation_lifecycle': re.compile(r'(?:addObserver:self|removeObserver:self)'),
    'cleanup_schedules_and_cancellations': re.compile(r'(?:performSelector:@selector\(removeHighlightedTerms\)|cancelPreviousPerformRequestsWithTarget:self)'),
    'logical_highlight_state': re.compile(r'searchHighlightsInvalidated'),
}
inventory = {name: [] for name in categories}
for name, source in sources.items():
    signature = None
    for number, line in enumerate(source.splitlines(), 1):
        if re.match(r'^\s*[-+]\s*\(', line):
            signature = line.strip()
        for category, pattern in categories.items():
            if pattern.search(line):
                # Unrelated perform-selector cancellation still belongs in this
                # inventory as context, but is not labeled cleanup-specific.
                inventory[category].append({'path': name, 'line': number,
                                            'method': signature, 'source': line.strip()})

check(len(inventory['generation_updates']) == 4, 'All four generation update sites are inventoried')
check(len(inventory['generation_reads']) == 1, 'The async acceptance predicate has one generation comparison site')
check('BOOL searchHighlightsInvalidated;' in header, 'Pending cleanup state belongs to each LinkingEditor instance')
check('storage != [textView textStorage]' in observer and 'NSTextStorageEditedCharacters' in observer,
      'The character observer rejects unrelated storage and attribute-only edits')
check(observer.index('++searchHighlightGeneration;') < observer.index('[textView invalidateSearchHighlights]'),
      'Shared character notification advances the async generation before logical cleanup invalidation')
check(refresh.index('++searchHighlightGeneration') < refresh.index('cancelLiteralRangesForOwner:') < refresh.index('if (!currentNote'),
      'Refresh changes its generation and cancels old literal work before any request-entry return')
check(all(value in refresh for value in ['!currentNote', '![prefsController highlightSearchTerms]',
      '![session searchResultsAreCurrent]', 'searchHasPendingComposition', 'if (row < 0) return;',
      'if ([kind isEqual:@"retained"]) return;']),
      'Request entry checks note, preferences, current results, composition, selection, and retained rows')
check('generation == searchHighlightGeneration && [session searchResultsAreCurrent] &&' in refresh and
      '[[session rowKeyAtIndex:[notesTableView primarySelectedRow]] isEqual:key]' in refresh,
      'Delivery requires the captured generation, current results, and the selected row key')
check('if (!error && isCurrent()) [textView setSearchHighlightRanges:ranges];' in refresh,
      'Final publication also rejects error completions')
check('if (isCurrent()) [service validateSourceRanges:' in refresh,
      'Fuzzy first-stage completion checks the same current-state predicate before validation')
check('NSString *displayedSource = [[textView string] copy];' in refresh and
      refresh.count('matchingSource:displayedSource') == 2,
      'Both request types pass the copied displayed source to range validation')
ordered = ['removeObserver:self name:NSTextStorageWillProcessEditingNotification',
           '[textView removeHighlightedTerms];', 'removeLayoutManager:layout',
           '[storage addLayoutManager:layout]', 'addObserver:self selector:@selector(searchSourceStorageWillProcessEditing:)']
positions = [switch.index(value) for value in ordered]
check(positions == sorted(positions), 'Note replacement removes the old observer, clears, detaches, attaches, and registers in that order')
check('if (editingSession) [[NSNotificationCenter defaultCenter] addObserver:self' in switch,
      'Empty editor storage has no shared-note observation registration')
check('[[NSNotificationCenter defaultCenter] removeObserver:self];' in method(browser, '- (void)dealloc'),
      'Browser deallocation removes its remaining notification observations')
check(invalidate.index('if (searchHighlightsInvalidated) return;') < invalidate.index('searchHighlightsInvalidated = YES;') < invalidate.index('performSelector:'),
      'Initial cleanup invalidation marks state before scheduling and coalesces repeat invalidations')
check(clear.index('cancelPreviousPerformRequestsWithTarget:self') < clear.index('NSTextStorageEditedCharacters'),
      'Cleanup cancels its older request before the character-edit branch')
check('searchHighlightsInvalidated = YES;' in clear and 'afterDelay:0.01' in clear and
      clear.index('return;') < clear.index('searchHighlightsInvalidated = NO;') < clear.index('removeTemporaryAttribute:'),
      'An open character edit preserves invalidation and retries, while the stable path clears state before native removal')
check('if (searchHighlightsInvalidated) return;' in publish and
      publish.index('if (searchHighlightsInvalidated) return;') < publish.index('addTemporaryAttribute:'),
      'Range publication cannot continue while cleanup remains deferred')
check('searchHighlightsInvalidated && [attributes objectForKey:NSBackgroundColorAttributeName]' in draw,
      'The drawing delegate suppresses stale backgrounds during pending cleanup')
check('cancelPreviousPerformRequestsWithTarget:self selector:@selector(removeHighlightedTerms) object:nil' in method(editor, '- (void)dealloc'),
      'Editor deallocation cancels its cleanup selector')

round1 = ROOT / 'Tests/SourceBackspaceReview/round1/kingsbury'
round2 = ROOT / 'Tests/SourceBackspaceReview/round2/kingsbury'
old1 = json.loads((round1 / 'interleavings.json').read_text())
old2 = json.loads((round2 / 'manifest.json').read_text())
probe1 = (round1 / 'interleavings.m').read_text()
probe2 = (round2 / 'probe.m').read_text()
coverage = [
    ('character and refresh generations', 2, 'old completion agrees with revision/request oracle'),
    ('row-key delivery check', 2, 'row-key change rejects a late callback before refresh'),
    ('selection returns to its old key', 2, 'ABA note selection rejects old same-key callback after refresh'),
    ('current-results delivery check', 2, 'pending result snapshot rejects callback'),
    ('error delivery check', 2, 'error completion does not publish'),
    ('fuzzy first-stage delivery', 2, 'obsolete fuzzy first stage never enters source validation'),
    ('fuzzy second-stage delivery', 2, 'edit between fuzzy stages rejects old validated ranges'),
    ('open character edit blocks publication', 2, 'even a current callback cannot install ranges during an open edit'),
    ('cleanup eventually settles in the old schedule', 2, 'all pending states settle after the edit closes'),
    ('detached owner ignores the previous storage', 1, 'detached owner ignores peer mutations'),
    ('new publication cancels the old callback', 1, 'new snapshot cancels pending old cleanup'),
    ('owner release after cancellation', 1, 'both editor owners release after callback cancellation'),
]
for concept, prior_round, assertion in coverage:
    check(assertion in (probe1 if prior_round == 1 else probe2), 'Saved earlier probe contains assertion for ' + concept)
check(old2['source_hashes_start'] == before == old2['source_hashes_end'],
      'The round 2 saved native probe hashes match the four current production files')
check(old2['results']['positive']['exit'] == 0 and
      'PASS: 57 checks; 12 exhaustive schedules' in old2['results']['positive']['stdout'],
      'The round 2 manifest records its earlier 57-check success and 12 schedules')
check(old1['exit'] == 0 and 'PASS: 13 native interleaving checks' in old1['output'],
      'The round 1 manifest records its separate earlier 13-check success')

after = hashes()
check(before == after, 'All four production hashes remain unchanged during this source review')
inventory['scope'] = 'Read-only source inventory and comparison with already saved evidence. No native or application execution.'
inventory['source_checks'] = checks
inventory['checks'] = len(checks)
inventory['acceptance_predicate'] = method(search, '- (void)refreshSearchHighlights')
inventory['earlier_coverage'] = [{'concept': name, 'round': prior, 'assertion': assertion} for name, prior, assertion in coverage]
inventory['earlier_evidence'] = {
    'round1': {'recorded_checks': 13, 'editor_hash_matches_current': old1['Sources/Editor/LinkingEditor.m'] == before[FILES[3]],
               'limit': 'Historical adapter used the pre-correction retry implementation; it did not execute the full note-switch method.'},
    'round2': {'recorded_checks': 57, 'recorded_schedules': 12, 'four_production_hashes_match_current': True,
               'limit': 'Historical AppKit adapter used stub services, browser state, and table selection. No result was rerun in this round.'},
}
inventory['source_only_paths_without_direct_assertion_in_these_state_probes'] = [
    'AppController textDidChange: and browserSessionSearchStateDidChange: generation increments',
    'Request-entry preference, missing-current-note, marked-search-composition, and retained-row gates',
    'The complete application note-switch and browser-deallocation methods',
]
manifest = {'base': '54ce3b8f94c382e8a4c20c871b8fb20dc30cc376', 'reviewed_head': head,
            'production_sha256_before': before, 'production_sha256_after': after,
            'prior_manifest_sha256': {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                                      for path in [round1 / 'interleavings.json', round2 / 'manifest.json']},
            'scope': inventory['scope']}
(HERE / 'inventory.json').write_text(json.dumps(inventory, indent=2) + '\n')
(HERE / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
output = '\n'.join('PASS: ' + value for value in checks) + '\n'
output += f'Completed {len(checks)} source and saved-evidence checks. No native tests ran.\n'
(HERE / 'output.txt').write_text(output)
print(output, end='')
