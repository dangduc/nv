#!/usr/bin/env python3
"""Benchmark production link decoration and an isolated line-cache experiment."""
from pathlib import Path
import argparse
import hashlib
import json
import platform
import subprocess

here = Path(__file__).resolve().parent
repo = here.parents[3]
arguments = argparse.ArgumentParser()
arguments.add_argument('--current', action='store_true', help='Measure the fixed worktree without overwriting the original evidence.')
args = arguments.parse_args()
out = repo / 'build/OrgSourceReview/round1/luu'
out.mkdir(parents=True, exist_ok=True)
source_path = 'Sources/Editor/AttributedPlainText.m'
source = (repo / source_path).read_text() if args.current else subprocess.check_output(['git', 'show', f'decc6788e1a746b5425f3cd248cd93071c98b8b2:{source_path}'], cwd=repo, text=True)
methods = source[source.index('- (void)addLinkAttributesForRange:'):source.index('- (void)addStrikethroughNearDoneTagsForRange:')]
strings = (repo / 'Sources/Utilities/NSString_NV.m').read_text()
escape = strings[strings.index('- (NSString*)stringWithPercentEscapes {'):strings.index('+ (NSString*)reasonStringFromCarbonFSError:')]
prefix = '''#import <Cocoa/Cocoa.h>
#import <CoreServices/CoreServices.h>
#import "AttributedPlainText.h"
@interface NSString (ProbeEscape)
- (NSString *)stringWithPercentEscapes;
@end
@implementation NSString (ProbeEscape)
''' + escape + '''\n@end
static BOOL _StringWithRangeIsProbablyObjC(NSString *string, NSRange blockRange);
@implementation NSMutableAttributedString (AttributedPlainText)
'''
line = 'NSUInteger lineEnd = MIN(NSMaxRange([string lineRangeForRange:NSMakeRange(cursor, 0)]), limit);'
variants = [('production-fixed', methods)]
if not args.current:
    assert methods.count(line) == 1
    cached = methods.replace('NSUInteger cursor = changedRange.location, limit = NSMaxRange(changedRange);',
        'NSUInteger cursor = changedRange.location, limit = NSMaxRange(changedRange), cachedLineEnd = changedRange.location;').replace(line,
        'if (cursor >= cachedLineEnd) cachedLineEnd = MIN(NSMaxRange([string lineRangeForRange:NSMakeRange(cursor, 0)]), limit);\n\t\tNSUInteger lineEnd = cachedLineEnd;')
    variants = [('production', methods), ('cached-line-experiment', cached)]
metadata = {'os': platform.platform(), 'architecture': 'x86_64 under Rosetta',
    'production_sha256': hashlib.sha256(source.encode()).hexdigest(),
    'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
    'scope': 'Exact extracted current production link methods.' if args.current else 'Exact extracted production link methods; cached variant changes only repeated line-boundary lookup.'}
(here / ('metadata-fixed.json' if args.current else 'metadata.json')).write_text(json.dumps(metadata, indent=2) + '\n')
for name, selected in variants:
    generated = prefix + selected + '\n@end\n' + (here / 'link-probe.m').read_text()
    generated_path = out / f'{name}.m'
    generated_path.write_text(generated)
    binary = out / name
    subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-O2', '-fblocks',
        '-framework', 'Cocoa', '-framework', 'CoreServices', '-Wno-deprecated-declarations',
        '-Wno-incomplete-implementation', '-I', str(repo / 'Sources/Editor'), str(generated_path), '-o', str(binary)], check=True)
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=240)
    (here / f'{name}.txt').write_text(result.stdout + result.stderr)
    print(name, result.stdout, result.stderr)
    result.check_returncode()
