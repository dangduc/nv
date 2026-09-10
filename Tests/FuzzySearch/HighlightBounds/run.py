#!/usr/bin/env python3
"""Exercise production async highlight and native TextKit methods without an app launch."""
import argparse
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
p = argparse.ArgumentParser()
p.add_argument('--sanitize', action='store_true')
p.add_argument('--negative-controls', action='store_true')
p.add_argument('--arch', choices=['arm64', 'x86_64'])
p.add_argument('--build-only', action='store_true')
a = p.parse_args()
OUT = ROOT / 'build/FuzzySearchHighlightBounds' / ('sanitize' if a.sanitize else (a.arch or 'native'))
OUT.mkdir(parents=True, exist_ok=True)

def methods(path, names):
    source = (ROOT / path).read_text()
    return '\n'.join(source[start:source.index('\n}', start)+2] for start in [source.index(name) for name in names])

refresh = methods('Sources/Browser/AppController_Search.m', ['- (void)refreshSearchHighlights'])
(OUT/'storage.inc').write_text(methods('Sources/Browser/AppController_Search.m', ['- (void)searchSourceStorageWillProcessEditing:']))
# This fixture checks range discovery and installation. Native rendering tests
# cover the browser appearance that supplies the highlight color.
editor = '- (NSDictionary *)currentSearchHighlightAttributes { return [prefsController searchTermHighlightAttributes]; }\n'
editor += methods('Sources/Editor/LinkingEditor.m', ['- (void)invalidateSearchHighlights', '- (void)removeHighlightedTerms', '- (void)setSearchHighlightRanges:', '- (NSRange)highlightTermsTemporarilyReturningFirstRange:'])
query = (ROOT / 'Sources/Search/NVSearchQuery.m').read_text()
flags = ['-O1' if a.sanitize else '-O2', '-g', '-fblocks', '-fno-objc-arc', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter', '-Wno-unused-variable', '-DUTF8PROC_STATIC', '-I'+str(OUT), '-I'+str(ROOT/'Sources/Search'), '-I'+str(ROOT/'ThirdParty/fzf-native')]
if a.arch: flags += ['-arch',a.arch,'-mmacosx-version-min=10.13' if a.arch=='x86_64' else '-mmacosx-version-min=11.0']
if a.sanitize: flags += ['-fsanitize=address,undefined','-fno-omit-frame-pointer']
objects=[]
for index,path in enumerate(['Sources/Search/NVFZF.c','ThirdParty/fzf-native/fzf.c','ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c','Sources/Search/NVSearchCorpus.m','Sources/Search/NVSearchService.m']):
    obj=OUT/f'{index}.o';args=flags if path.endswith('.m') else [f for f in flags if f not in ['-fno-objc-arc','-Wextra','-Werror']]+['-std=c11']
    subprocess.run(['xcrun','clang',*args,'-c',str(ROOT/path),'-o',str(obj)],check=True);objects.append(str(obj))

EXPECTED_MUTATION_FAILURES = {
    'missing_generation': 'stale query generation cannot install highlights',
    'missing_row_context': 'changed duplicate occurrence rejects old row highlights',
    'uncancelled_discovery': 'literal discovery obeys cancellation before full scan',
    'unbounded_discovery': 'literal discovery stops at occurrence cap before allocation grows',
    'uncapped_editor': 'editor independently caps oversized native range input',
    'uncoalesced_invalidation': 'repeated invalidations coalesce one delayed selector',
    'uncancelled_clear': 'explicit cleanup cancels the queued selector',
    'unsafe_character_edit_clear': 'cleanup and range publication defer all layout mutation during character processing',
    'zero_delay_edit_retry': 'open character batch retries with a positive minimum delay',
    'unsafe_character_edit_publication': 'cleanup and range publication defer all layout mutation during character processing',
    'missing_source_validation': 'canonical equivalents with different UTF16 reject snapshot offsets',
}

def run_case(name, refresh_text, editor_text, query_text, positive, object_files=None):
    if not positive and name not in EXPECTED_MUTATION_FAILURES:
        raise SystemExit('Mutation has no expected assertion: '+name)
    (OUT/'refresh.inc').write_text(refresh_text);(OUT/'editor.inc').write_text(editor_text);(OUT/'query.m').write_text(query_text)
    binary=OUT/name
    subprocess.run(['xcrun','clang',*flags,str(HERE/'probe.m'),str(OUT/'query.m'),*(object_files or objects),'-framework','Cocoa','-o',str(binary)],check=True)
    if a.build_only: return
    result=subprocess.run([str(binary)],env=dict(os.environ,UBSAN_OPTIONS='halt_on_error=1'),capture_output=True,text=True,timeout=40)
    (OUT/(name+'.log')).write_text(result.stdout+result.stderr)
    if positive and result.returncode: raise SystemExit(result.stdout+result.stderr)
    if not positive:
        expected = 'FAIL: '+EXPECTED_MUTATION_FAILURES[name]
        if result.returncode != 1 or expected not in result.stderr.splitlines():
            raise SystemExit(f'Mutation did not fail at its expected assertion: {name} (exit {result.returncode})\n'+result.stdout+result.stderr)
    print(result.stdout if positive else 'REJECTED: '+name+' '+result.stderr.strip(),end='\n')

run_case('positive',refresh,editor,query,True)
if a.negative_controls and not a.build_only:
    mutants=[('missing_generation',refresh.replace('generation == searchHighlightGeneration &&','YES &&'),editor,query),('missing_row_context',refresh.replace('[[session rowKeyAtIndex:[notesTableView primarySelectedRow]] isEqual:key]','YES'),editor,query),('uncancelled_discovery',refresh,editor,query.replace('if (cancelled && cancelled()) return nil;','if (NO) return nil;')),('unbounded_discovery',refresh,editor,query.replace('NSUInteger occurrences = 0, length = [string length];','maximumCount = NSUIntegerMax; NSUInteger occurrences = 0, length = [string length];')),('uncapped_editor',refresh,editor.replace('if (displayed++ == NVSearchMaximumDisplayedRanges) break;',''),query)]
    mutants += [
        ('uncoalesced_invalidation', refresh, editor.replace('    if (!hasSearchHighlights || searchHighlightsInvalidated) return;\n    searchHighlightsInvalidated = YES;', '    searchHighlightsInvalidated = YES;'), query),
        ('uncancelled_clear', refresh, editor.replace('    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(removeHighlightedTerms) object:nil];\n', ''), query),
        ('unsafe_character_edit_clear', refresh, editor.replace('    if ([[self textStorage] editedMask] & NSTextStorageEditedCharacters) {', '    if (NO) {'), query),
        ('zero_delay_edit_retry', refresh, editor.replace('afterDelay:0.01', 'afterDelay:0'), query),
        ('unsafe_character_edit_publication', refresh, editor.replace('    [self removeHighlightedTerms];\n    if (searchHighlightsInvalidated || ([[self textStorage] editedMask] & NSTextStorageEditedCharacters)) return;\n', '    [self removeHighlightedTerms];\n'), query),
    ]
    for name,r,e,q in mutants:
        if (r,e,q)==(refresh,editor,query): raise SystemExit('Mutation no longer applies: '+name)
        run_case(name,r,e,q,False)
    service_source=(ROOT/'Sources/Search/NVSearchService.m').read_text()
    unsafe=service_source.replace('work->cancel && [work->source isEqual:work->matchingSource]', 'work->cancel')
    assert unsafe!=service_source
    (OUT/'unsafe-service.m').write_text(unsafe)
    unsafe_object=OUT/'unsafe-service.o'
    subprocess.run(['xcrun','clang',*flags,'-c',str(OUT/'unsafe-service.m'),'-o',str(unsafe_object)],check=True)
    run_case('missing_source_validation',refresh,editor,query,False,[*objects[:-1],str(unsafe_object)])
# Leave generated sources showing the production methods.
(OUT/'refresh.inc').write_text(refresh);(OUT/'editor.inc').write_text(editor);(OUT/'query.m').write_text(query)
