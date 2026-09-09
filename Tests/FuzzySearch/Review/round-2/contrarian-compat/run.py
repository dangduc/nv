#!/usr/bin/env python3
"""Run compatibility probes against production methods and real native search."""
import argparse
import hashlib
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
sys.path.insert(0, str(ROOT / 'Tests'))
from compiler_support import include_flags

p = argparse.ArgumentParser()
p.add_argument('--sanitize', action='store_true')
p.add_argument('--compile-only', action='store_true')
p.add_argument('--arch', choices=['arm64', 'x86_64'], default='arm64')
a = p.parse_args()
out = ROOT / 'build/FuzzySearchReview/round-2/contrarian-compat' / (a.arch + ('-sanitize' if a.sanitize else ''))
out.mkdir(parents=True, exist_ok=True)
spans = []
SOURCE_ROOT = out / 'source-snapshot'
for source_dir in ['Sources', 'Config', 'ThirdParty/fzf-native']:
    shutil.copytree(ROOT / source_dir, SOURCE_ROOT / source_dir, dirs_exist_ok=True)
source_head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()

def section(path, first, last):
    s = (SOURCE_ROOT / path).read_text()
    start = s.index(first)
    end = s.index(last, start)
    value = s[start:end]
    spans.append({'path': path, 'line': s[:start].count('\n') + 1, 'signature': first,
                  'sha256': hashlib.sha256(value.encode()).hexdigest(),
                  'equals_6d66102': value in subprocess.check_output(['git', 'show', '6d66102:' + path], text=True)})
    return value

def method(path, signature):
    s = (SOURCE_ROOT / path).read_text()
    start = s.index(signature)
    opening = s.index('{', start)
    end = s.index('\n}', opening) + 2
    if '\n' not in s[start:opening]:
        line_end = s.index('\n', start)
        if '}' in s[opening:line_end]:
            end = line_end
    value = s[start:end]
    spans.append({'path': path, 'line': s[:start].count('\n') + 1, 'signature': signature,
                  'sha256': hashlib.sha256(value.encode()).hexdigest(),
                  'equals_6d66102': value in subprocess.check_output(['git', 'show', '6d66102:' + path], text=True)})
    return value

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
        '- (void)tableViewSelectionDidChange:', '- (void)processChangedSelectionForTable:',
        '- (void)restoreListStateUsingPreferences', '- (void)searchForString:(NSString*)string',
        '- (void)bookmarksController:', '- (BOOL)control:(NSControl *)control textView:',
        '- (NSString*)fieldSearchString', '- (void)cacheTypedStringIfNecessary:'],
    'Sources/Browser/AppController_MultipleWindows.m': [
        '- (void)restoreBrowserWindowState:', '- (void)applyRestoredSearchNoteState:',
        '- (void)attachLibrary:(NotationController *)library finishingOldLibrary:'],
    'Sources/Browser/AppController_Importing.m': ['- (BOOL)interpretNVURL:']
}
if '- (void)cancelTransientSearchIntents' in (SOURCE_ROOT / 'Sources/Browser/AppController_Search.m').read_text():
    groups['Sources/Browser/AppController_Search.m'].append('- (void)cancelTransientSearchIntents')
(out / 'production-methods.inc').write_text('\n'.join(method(path, sig) for path, sigs in groups.items() for sig in sigs))
(out / 'persistence-models.inc').write_text(
    section('Sources/Browser/BookmarksController.m', 'static NSString *BMSearchStringKey', '#define MovedBookmarksType') + '\n' +
    section('Sources/Browser/SavedSearchesController.m', 'static NSString *SSSearchStringKey', '#define MovedSearchesType') + '\n' +
    '@implementation NSString (ProductionUUID)\n' +
    method('Sources/Utilities/NSString_NV.m', '- (CFUUIDBytes)uuidBytes') + '\n@end\n')
(out / 'defaults.inc').write_text('''
@interface ReviewDefaults : NSObject { @public NSMutableDictionary *values; }
+ (id)standardUserDefaults;
- (id)objectForKey:(NSString *)key;
- (double)doubleForKey:(NSString *)key;
- (void)setObject:(id)object forKey:(NSString *)key;
- (void)removeObjectForKey:(NSString *)key;
- (void)setDouble:(double)value forKey:(NSString *)key;
@end
@implementation ReviewDefaults
+ (id)standardUserDefaults { static id d; if (!d) d = [self new]; return d; }
- (id)init { if ((self=[super init])) values=[NSMutableDictionary new]; return self; }
- (id)objectForKey:(NSString *)key { return values[key]; }
- (double)doubleForKey:(NSString *)key { return [values[key] doubleValue]; }
- (void)setObject:(id)object forKey:(NSString *)key { values[key] = object; }
- (void)removeObjectForKey:(NSString *)key { [values removeObjectForKey:key]; }
- (void)setDouble:(double)value forKey:(NSString *)key { values[key] = @(value); }
- (void)dealloc { [values release]; [super dealloc]; }
@end
static NSString *LastSearchStringKey=@"LastSearchString", *LastSearchModeKey=@"LastSearchMode", *LastSearchResultRowKey=@"LastSearchResultRowKey";
static NSString *LastSelectedNoteUUIDBytesKey=@"LastSelectedNoteUUIDBytes", *LastScrollOffsetKey=@"LastScrollOffset";
#define SEND_CALLBACKS() ((void)0)
@implementation GlobalPrefs (ProductionPersistence)
''' + section('Sources/Preferences/GlobalPrefs.m', '- (void)setLastSearchString:', '- (void)saveCurrentBookmarksFromSender:') + '\n@end\n')
(out / 'dual-field.inc').write_text(section('Sources/UI/DualField.m', '- (BOOL)hasFollowedLinks', '- (void)snapback:'))
fixture = (ROOT / 'Tests/FuzzySearch/Browser/browser-tests.m').read_text()
prefix = fixture[:fixture.index('// Run the exact production occurrence-selection methods')]
helpers = fixture[fixture.index('static BOOL Spin('):fixture.index('int main(void)')]
validation = section('Sources/Browser/AppController_MultipleWindows.m', 'static NSDictionary *ValidatedBodyState', '@implementation')
(out / 'probe.m').write_text(prefix + helpers + validation + (HERE / 'support.m').read_text() + (HERE / 'cases.m').read_text())
flags = ['-arch', a.arch, '-mmacosx-version-min=' + ('10.13' if a.arch == 'x86_64' else '11.0'), '-g', '-O1' if a.sanitize else '-O2', '-DUTF8PROC_STATIC',
         '-I' + str(out), '-I' + str(SOURCE_ROOT / 'ThirdParty/fzf-native'), *include_flags(SOURCE_ROOT), *include_flags(ROOT)]
if a.sanitize:
    flags += ['-fsanitize=address,undefined', '-fno-omit-frame-pointer']
sources = ['Sources/Search/NVFZF.c', 'ThirdParty/fzf-native/fzf.c', 'ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c',
           'Sources/Search/NVSearchQuery.m', 'Sources/Search/NVSearchCorpus.m', 'Sources/Search/NVSearchService.m',
           'Sources/Browser/NVBrowserSession.m', str((out / 'probe.m').relative_to(ROOT))]
objects = []
for index, source in enumerate(sources):
    obj = out / f'{index}.o'
    language = ['-fblocks', '-fno-objc-arc', '-Wno-deprecated-declarations', '-Wno-incomplete-implementation',
                '-Wno-protocol', '-Wno-incompatible-pointer-types', '-Wno-objc-method-access',
                '-include', str(SOURCE_ROOT / 'Config/Notation_Prefix.pch')] if source.endswith('.m') else ['-std=c11']
    subprocess.run(['xcrun', 'clang', *flags, *language, '-c', str((SOURCE_ROOT if source.startswith(('Sources/', 'ThirdParty/')) else ROOT) / source), '-o', str(obj)], check=True, timeout=60)
    objects.append(str(obj))
binary = out / 'probe'
subprocess.run(['xcrun', 'clang', *flags, *objects, '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(binary)], check=True, timeout=60)
environment = dict(os.environ)
environment['UBSAN_OPTIONS'] = 'halt_on_error=1'
result = None if a.compile_only else subprocess.run([str(binary)], capture_output=True, text=True, env=environment, timeout=30)
if result:
    print(result.stdout, end='')
    print(result.stderr, end='')
inputs = sorted(set([s['path'] for s in spans] + sources[:-1] + ['Tests/FuzzySearch/Browser/browser-tests.m',
    'Sources/Browser/AppController.h', 'Sources/Browser/NVBrowserSession.h', 'Sources/Search/NVSearchService.h',
    'Sources/Browser/BookmarksController.h', 'Sources/Browser/SavedSearchesController.h', 'Sources/Preferences/GlobalPrefs.h',
    str(HERE.relative_to(ROOT) / 'support.m'), str(HERE.relative_to(ROOT) / 'cases.m'), str(HERE.relative_to(ROOT) / 'run.py')]))
record = {'command': [sys.executable, *sys.argv], 'head_at_snapshot': source_head, 'source_snapshot': str(SOURCE_ROOT.relative_to(ROOT)),
    'exit_code': result.returncode if result else None, 'compile_only': a.compile_only, 'architecture': a.arch,
    'stdout': result.stdout if result else '', 'stderr': result.stderr if result else '', 'production_methods': spans,
    'sha256': {source: hashlib.sha256(((SOURCE_ROOT if source.startswith(('Sources/', 'ThirdParty/')) else ROOT) / source).read_bytes()).hexdigest() for source in inputs},
    'production_equal_6d66102': {source: (SOURCE_ROOT / source).read_bytes() == subprocess.check_output(['git', 'show', '6d66102:' + source])
        for source in inputs if source.startswith('Sources/')}}
name = 'compile-only' if a.compile_only else 'sanitize' if a.sanitize else 'native'
(HERE / (name + '-results.json')).write_text(json.dumps(record, indent=2) + '\n')
raise SystemExit(result.returncode if result else 0)
