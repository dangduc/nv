#!/usr/bin/env python3
"""Exercise unchanged production browser intent methods using native arm64."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
sys.path.insert(0, str(ROOT / 'Tests'))
from compiler_support import include_flags
p = argparse.ArgumentParser()
p.add_argument('--sanitize', action='store_true')
p.add_argument('--expect-fixed', action='store_true', help='Require cancellation and complete Reveal instead of the recorded failure witnesses.')
a = p.parse_args()
out = ROOT / 'build/FuzzySearchReview/round-1/kingsbury' / ('sanitize' if a.sanitize else 'native')
out.mkdir(parents=True, exist_ok=True)
fixture = (ROOT / 'Tests/FuzzySearch/Browser/browser-tests.m').read_text()
prefix = fixture[:fixture.index('// Run the exact production occurrence-selection methods')]
helpers = fixture[fixture.index('static BOOL Spin('):fixture.index('int main(void)')]
groups = {
    'Sources/Browser/AppController_Search.m': [
        '- (NSString *)searchMode', '- (NSString *)selectedSearchResultRowKey', '- (BOOL)searchFieldHasFocus',
        '- (void)cancelSearchIntents', '- (void)searchForString:', '- (IBAction)selectSearchMode:',
        '- (IBAction)retrySearch:', '- (void)showSearchProgress', '- (void)browserSessionSearchStateDidChange:',
        '- (void)browserSessionSearchDidComplete:', '- (void)performSearchReturn'],
    'Sources/Browser/AppController.m': [
        '- (void)controlTextDidChange:', '- (void)controlTextDidEndEditing:',
        '- (void)windowDidResignKey:', '- (void)windowWillClose:', '- (void)cancelOperation:',
        '- (NSUInteger)revealNote:', '- (void)notation:(NotationController*)notation revealNotes:',
        '- (void)tableViewSelectionDidChange:'],
    'Sources/Browser/AppController_MultipleWindows.m': [
        '- (void)restoreBrowserWindowState:', '- (void)applyRestoredSearchNoteState:',
        '- (void)attachLibrary:(NotationController *)library finishingOldLibrary:']
}
methods = []
spans = []
for path, signatures in groups.items():
    production = (ROOT / path).read_text()
    for signature in signatures:
        start = production.index(signature)
        opening = production.index('{', start)
        # Multi-line methods end at column zero in these production files.
        end = production.index('\n}', opening) + 2
        if '\n' not in production[start:opening]:
            line_end = production.index('\n', start)
            if '}' in production[opening:line_end]:
                end = line_end
        methods.append(production[start:end])
        spans.append({'path': path, 'line': production[:start].count('\n') + 1, 'signature': signature,
                      'sha256': hashlib.sha256(production[start:end].encode()).hexdigest()})
(out / 'production-methods.inc').write_text('\n'.join(methods))
multiple = (ROOT / 'Sources/Browser/AppController_MultipleWindows.m').read_text()
validation = multiple[multiple.index('static NSDictionary *ValidatedBodyState'):multiple.index('@implementation')]
(out / 'state-probe.m').write_text(prefix + helpers + validation + (HERE / 'probe-body.m').read_text())
flags = ['-arch', 'arm64', '-g', '-O1' if a.sanitize else '-O2', '-DUTF8PROC_STATIC',
         '-I' + str(out), '-I' + str(ROOT / 'ThirdParty/fzf-native'), *include_flags(ROOT)]
if a.sanitize:
    flags += ['-fsanitize=address,undefined', '-fno-omit-frame-pointer']
if a.expect_fixed:
    flags += ['-DNV_REVIEW_EXPECT_FIXED=1']
sources = ['Sources/Search/NVFZF.c', 'ThirdParty/fzf-native/fzf.c',
           'ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c', 'Sources/Search/NVSearchQuery.m',
           'Sources/Search/NVSearchCorpus.m', 'Sources/Search/NVSearchService.m',
           'Sources/Browser/NVBrowserSession.m', str((out / 'state-probe.m').relative_to(ROOT))]
objects = []
for index, source in enumerate(sources):
    obj = out / f'{index}.o'
    language = ['-fblocks', '-fno-objc-arc', '-Wno-deprecated-declarations', '-Wno-incomplete-implementation',
                '-Wno-protocol', '-Wno-incompatible-pointer-types', '-Wno-objc-method-access',
                '-include', str(ROOT / 'Config/Notation_Prefix.pch')] if source.endswith('.m') else ['-std=c11']
    subprocess.run(['xcrun', 'clang', *flags, *language, '-c', str(ROOT / source), '-o', str(obj)], check=True)
    objects.append(str(obj))
binary = out / 'state-probe'
subprocess.run(['xcrun', 'clang', *flags, *objects, '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(binary)], check=True)
environment = dict(os.environ)
if a.sanitize:
    environment['UBSAN_OPTIONS'] = 'halt_on_error=1'
result = subprocess.run([str(binary)], capture_output=True, text=True, env=environment, timeout=30)
print(result.stdout, end='')
print(result.stderr, end='')
inputs = [*groups, 'Tests/FuzzySearch/Browser/browser-tests.m', str(HERE.relative_to(ROOT) / 'probe-body.m'), *sources[:-1]]
record = {'command': ['python3', str(Path(__file__).relative_to(ROOT)), *(['--sanitize'] if a.sanitize else []), *(['--expect-fixed'] if a.expect_fixed else [])],
          'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
          'exit_code': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr, 'production_methods': spans,
          'sha256': {source: hashlib.sha256((ROOT / source).read_bytes()).hexdigest() for source in inputs}}
(HERE / (('fixed-' if a.expect_fixed else '') + ('sanitize-results.json' if a.sanitize else 'native-results.json'))).write_text(json.dumps(record, indent=2) + '\n')
raise SystemExit(result.returncode)
