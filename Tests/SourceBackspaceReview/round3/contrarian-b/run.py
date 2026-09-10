#!/usr/bin/env python3
"""Static maintenance/compatibility inventory; reads source and installed SDK headers."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = '54ce3b8f94c382e8a4c20c871b8fb20dc30cc376'
FINAL_PRODUCTION = 'c2209e2e6ca1194c3a3ffe361e826860e4e830d8'
FILES = ['Sources/Browser/AppController.m', 'Sources/Browser/AppController_Search.m',
         'Sources/Editor/LinkingEditor.h', 'Sources/Editor/LinkingEditor.m']

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True)

def hashes():
    return {path: hashlib.sha256((ROOT/path).read_bytes()).hexdigest() for path in FILES}

def method(source, name):
    start = source.index(name)
    return source[start:source.index('\n}', start)+2]

before = hashes()
head = git('rev-parse', 'HEAD').strip()
sdk = Path(subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip())
headers = sdk/'System/Library/Frameworks/Foundation.framework/Headers'
runloop = (headers/'NSRunLoop.h').read_text()
array = (headers/'NSArray.h').read_text()
source = {path: (ROOT/path).read_text() for path in FILES}
editor = source[FILES[3]]
header = source[FILES[2]]
base_editor = git('show', BASE+':'+FILES[3])
project = (ROOT/'Notation.xcodeproj/project.pbxproj').read_text()
checks = []
facts = {}

def check(value, description):
    checks.append({'passed': bool(value), 'description': description})
    if not value:
        raise AssertionError(description)

project_targets = re.findall(r'MACOSX_DEPLOYMENT_TARGET = ([0-9.]+);', project)
facts['project_deployment_targets'] = project_targets
check(project_targets and set(project_targets) == {'10.9'}, 'Stored Xcode configurations retain macOS 10.9 deployment targets.')
check('MACOSX_DEPLOYMENT_TARGET=10.13' in (ROOT/'AGENTS.md').read_text() and
      'MACOSX_DEPLOYMENT_TARGET=10.13' in (ROOT/'.github/workflows/macos.yml').read_text(),
      'Documented Development and CI commands explicitly build for macOS 10.13.')
common_declaration = next(line for line in runloop.splitlines() if 'NSRunLoopCommonModes API_AVAILABLE' in line)
facts['sdk_common_modes_declaration'] = common_declaration
check('macos(10.5)' in common_declaration, 'Installed Apple SDK marks NSRunLoopCommonModes available since macOS 10.5.')
perform_declaration = next(line for line in runloop.splitlines() if line.startswith('- (void)performSelector:') and 'afterDelay:' in line and 'inModes:' in line)
cancel_declaration = next(line for line in runloop.splitlines() if line.startswith('+ (void)cancelPreviousPerformRequestsWithTarget:') and 'selector:' in line)
array_declaration = next(line for line in array.splitlines() if line.startswith('+ (instancetype)arrayWithObjects:') and 'count:' in line)
facts.update({'sdk_perform_declaration': perform_declaration, 'sdk_cancel_declaration': cancel_declaration,
              'sdk_array_creation_declaration': array_declaration})
for name, declaration in [('Delayed selector', perform_declaration), ('Selector cancellation', cancel_declaration), ('NSArray object/count creation', array_declaration)]:
    check('API_UNAVAILABLE' not in declaration and 'API_AVAILABLE' not in declaration,
          name+' is declared without a later platform availability restriction in the installed SDK.')
check('- (void)invalidateSearchHighlights;' in header and editor.count('- (void)invalidateSearchHighlights {') == 1,
      'The new invalidation selector has a matching public declaration and one implementation.')
check('- (void)removeHighlightedTerms;' in header and editor.count('- (void)removeHighlightedTerms {') == 1,
      'The scheduled no-argument cleanup selector has a matching declaration and one implementation.')
facts['base_editor_array_literal_count'] = base_editor.count('@[')
check(base_editor.count('@[') > 0, 'The editor already uses Objective-C array literals in the base revision.')
check('@[NSRunLoopCommonModes]' in editor and '@[NSRunLoopCommonModes]' not in base_editor,
      'New scheduling uses the existing Objective-C literal syntax with the SDK common-mode constant.')
check('CLANG_ENABLE_OBJC_ARC = YES' not in project and '-fobjc-arc' not in project,
      'The patch does not enable ARC in the project configuration.')
render = method(editor, '- (NSDictionary *)layoutManager:(NSLayoutManager *)manager shouldUseTemporaryAttributes:')
check('NSMutableDictionary *display = [[attributes mutableCopy] autorelease];' in render,
      'The new mutable drawing dictionary balances its copy ownership with autorelease.')
check('BOOL searchHighlightsInvalidated;' in header,
      'New persistent editor state is a primitive BOOL with no object ownership.')
invalidate = method(editor, '- (void)invalidateSearchHighlights')
cleanup = method(editor, '- (void)removeHighlightedTerms')
dealloc = method(editor, '- (void)dealloc')
cancellation = '[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(removeHighlightedTerms) object:nil];'
check(cancellation in cleanup and cancellation in dealloc and dealloc.index(cancellation) < dealloc.index('[super dealloc]'),
      'Explicit cleanup and editor deallocation cancel the same target/selector/object request before teardown.')
check('[super dealloc];' in dealloc,
      'The existing manual-memory-management superclass teardown remains present.')
check('if (searchHighlightsInvalidated) return;' in invalidate and 'withObject:nil afterDelay:0 inModes:@[NSRunLoopCommonModes]' in invalidate,
      'Initial scheduling coalesces requests and uses common run-loop modes.')
check(cleanup.count('afterDelay:0.01') == 1 and editor.count('afterDelay:0.01') == 1 and
      'withObject:nil afterDelay:0.01 inModes:@[NSRunLoopCommonModes]' in cleanup,
      'The 10 ms retry is a single production literal, and uses the same mode list as initial scheduling.')
check(cleanup.index('editedMask') < cleanup.index('afterDelay:0.01') < cleanup.index('        return;') < cleanup.index('removeTemporaryAttribute'),
      'A common-mode retry still checks character-edit state and returns before unsafe cleanup.')
check('A nested run loop can run before endEditing. Avoid retrying at zero delay.' in cleanup,
      'The production comment explains why a dirty edit receives a nonzero retry delay.')
architecture = (ROOT/'architecture.md').read_text()
check('A coalesced callback removes the attributes after TextKit processes the edit' in architecture and
      'Fresh highlights cancel pending cleanup.' in architecture,
      'Architecture documentation describes the cleanup boundary and fresh-result cancellation.')
review_index = (ROOT/'Tests/SourceBackspaceReview/README.md').read_text()
check('changed retries to 10 ms' in review_index and 'fixes/retry/report.md' in review_index,
      'The review index documents the 10 ms correction and links its rationale and evidence.')
bounds = (ROOT/'Tests/FuzzySearch/HighlightBounds/probe.m').read_text()
check('lastClearDelay >= .01' in bounds and 'open character batch retries with a positive minimum delay' in bounds,
      'The maintained highlight probe explicitly guards the retry-delay lower bound.')
check('SourceBackspace/README.md' in (ROOT/'Tests/README.md').read_text() and
      'python3 Tests/SourceBackspace/run.py' in (ROOT/'Tests/SourceBackspace/README.md').read_text(),
      'The test index links the focused suite and the focused guide gives its command.')
aggregate = (ROOT/'Tests/run-regression-tests.py').read_text()
check("'SourceBackspace/run.py'" in aggregate and "'FuzzySearch/HighlightBounds/run.py'" in aggregate,
      'The aggregate regression runner includes both maintained affected suites.')
production_paths = ['Sources', 'Resources', 'Config', 'Notation.xcodeproj']
changed_production = git('diff', '--name-only', FINAL_PRODUCTION, '--', *production_paths).splitlines()
facts['production_paths_changed_after_final_production_commit'] = changed_production
check(not changed_production, 'No source, resource, config, or Xcode project content changed after c2209e2.')
for path in FILES:
    check(source[path] == git('show', FINAL_PRODUCTION+':'+path), path+' remains byte-identical to the final production commit.')
after = hashes()
check(before == after, 'Four production hashes match before and after this source-only inventory.')
manifest = {'reviewed_head': head, 'head_end': git('rev-parse', 'HEAD').strip(),
            'base': BASE, 'final_production_commit': FINAL_PRODUCTION,
            'production_hashes_before': before, 'production_hashes_after': after,
            'sdk_path': str(sdk),
            'sdk_header_sha256': {name: hashlib.sha256((headers/name).read_bytes()).hexdigest() for name in ['NSRunLoop.h', 'NSArray.h']},
            'checks': checks, 'facts': facts,
            'scope': 'Static source and installed SDK-header review only. No compilation, native execution, GUI, crash reproduction, mutations, or old-OS validation.'}
(HERE/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
lines = ['SOURCE-ONLY MAINTENANCE/COMPATIBILITY REVIEW', 'HEAD: '+head, 'SDK: '+str(sdk),
         *['PASS: '+item['description'] for item in checks], '', 'RECORDED FACTS', json.dumps(facts, indent=2),
         f'STATIC CHECKS PASSED: {len(checks)}', 'No new runtime validation.']
(HERE/'output.txt').write_text('\n'.join(lines)+'\n')
print('\n'.join(lines))
