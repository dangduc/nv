#!/usr/bin/env python3
"""Read source ownership and call sites; write only this review's evidence files.

This is a textual inventory, not a compiler, a runtime test, or call-graph proof.
"""
import hashlib
import json
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
PRODUCTION = [
    'Sources/Browser/AppController.m',
    'Sources/Browser/AppController_Search.m',
    'Sources/Editor/LinkingEditor.h',
    'Sources/Editor/LinkingEditor.m',
]
APIS = [
    'removeHighlightedTerms', 'invalidateSearchHighlights',
    'setSearchHighlightRanges', 'highlightRangesTemporarily',
    'highlightTermsTemporarilyReturningFirstRange',
]

def hashes():
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
            for name in PRODUCTION}

def head():
    return subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()

before, start = hashes(), head()
inventory = {name: {'declarations': [], 'definitions': [], 'direct_calls': [], 'selector_references': []}
             for name in APIS}
state = {'searchHighlightsInvalidated': [], 'searchHighlightGeneration': []}
files = sorted(path for path in (ROOT / 'Sources').rglob('*')
               if path.suffix in {'.h', '.m', '.mm', '.c'})
for path in files:
    enclosing = None
    in_comment = False
    for number, raw in enumerate(path.read_text(errors='replace').splitlines(), 1):
        # All selected identifiers occur on single source lines. Remove comments
        # so this inventory does not count commented-out legacy calls.
        clean = raw
        if in_comment:
            if '*/' not in clean:
                continue
            clean = clean.split('*/', 1)[1]
            in_comment = False
        while '/*' in clean:
            prefix, rest = clean.split('/*', 1)
            if '*/' in rest:
                clean = prefix + rest.split('*/', 1)[1]
            else:
                clean, in_comment = prefix, True
                break
        clean = clean.split('//', 1)[0].strip()
        signature = re.match(r'^[-+]\s*\([^)]*\)\s*(\w+)', clean)
        if signature:
            enclosing = clean
        site = {'path': str(path.relative_to(ROOT)), 'line': number,
                'method': enclosing, 'source': raw.strip()}
        for name in APIS:
            if signature and signature.group(1) == name:
                inventory[name]['declarations' if path.suffix == '.h' else 'definitions'].append(site)
            elif re.search(r'@selector\(\s*' + name + r'\b', clean):
                inventory[name]['selector_references'].append(site)
            elif re.search(r'\[[^\n]*\b' + name + r'(?:\s|:|\])', clean):
                inventory[name]['direct_calls'].append(site)
        for name in state:
            if re.search(r'\b' + name + r'\b', clean):
                state[name].append(site)

responsibilities = {}
queries = {
    'source_character_observer': ('Sources/Browser/AppController_Search.m',
        '- (void)searchSourceStorageWillProcessEditing:(NSNotification *)notification {'),
    'source_highlight_request': ('Sources/Browser/AppController_Search.m', '- (void)refreshSearchHighlights {'),
    'storage_attachment': ('Sources/Browser/AppController.m',
        '- (void)_setCurrentNote:(NoteObject *)aNote finishingEditing:(BOOL)finishOldEditing {'),
    'editor_invalidation': ('Sources/Editor/LinkingEditor.m', '- (void)invalidateSearchHighlights {'),
    'editor_cleanup': ('Sources/Editor/LinkingEditor.m', '- (void)removeHighlightedTerms {'),
    'editor_publication': ('Sources/Editor/LinkingEditor.m', '- (void)setSearchHighlightRanges:(NSArray *)ranges {'),
}
for purpose, (name, signature) in queries.items():
    source = (ROOT / name).read_text()
    beginning = source.index(signature)
    end, depth = source.index('{', beginning) + 1, 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    responsibilities[purpose] = {'path': name, 'line': source[:beginning].count('\n') + 1,
                                 'source': source[beginning:end]}
architecture = (ROOT / 'architecture.md').read_text()
start_doc = architecture.index('Search highlights use only temporary background attributes')
end_doc = architecture.index('\n\n', start_doc)
documentation = {'path': 'architecture.md', 'line': architecture[:start_doc].count('\n') + 1,
                 'source': architecture[start_doc:end_doc]}

# These checks establish inventory consistency, not execution behavior.
assert all(len(data['declarations']) == 1 and len(data['definitions']) == 1
           for data in inventory.values())
assert all(site['path'].startswith('Sources/Editor/LinkingEditor.')
           for site in state['searchHighlightsInvalidated'])
assert any(site['path'] == 'Sources/Browser/AppController_Search.m'
           for site in inventory['invalidateSearchHighlights']['direct_calls'])
base_header = subprocess.check_output(['git', 'show', '54ce3b8:Sources/Editor/LinkingEditor.h'], cwd=ROOT, text=True)
base_surface = {name: bool(re.search(r'\b' + name + r'\b', base_header)) for name in APIS}
output = {'base_header_api_presence_at_54ce3b8': base_surface, 'scope': 'Static source inventory; no native execution or runtime validation.',
          'source_files_read': len(files), 'apis': inventory, 'state_references': state,
          'responsibility_excerpts': responsibilities, 'architecture_excerpt': documentation,
          'inventory_consistency_checks': 3}
(HERE / 'output.json').write_text(json.dumps(output, indent=2) + '\n')
after = hashes()
manifest = {'tested_head_start': start, 'head_end': head(),
            'production_sha256_before': before, 'production_sha256_after': after,
            'production_unchanged': before == after,
            'architecture_sha256': hashlib.sha256(architecture.encode()).hexdigest(),
            'evidence_kind': 'Static textual source inventory',
            'native_execution': False,
            'limitations': ['Text matching does not prove dynamic dispatch or runtime reachability.',
                            'No editor execution, lifecycle experiments, or crash reproduction.',
                            'No new macOS runtime validation.']}
(HERE / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
assert before == after
for name, data in inventory.items():
    print(name + ': ' + ', '.join(f'{key}={len(sites)}' for key, sites in data.items()))
print(f'Source files read: {len(files)}. Static consistency checks: 3. Native executions: 0.')
