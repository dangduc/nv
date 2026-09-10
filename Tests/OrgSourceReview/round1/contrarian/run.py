#!/usr/bin/env python3
"""Run independent ordinary-Org semantic fixtures through production code."""
from pathlib import Path
import argparse
import hashlib
import json
import platform
import re
import subprocess

here = Path(__file__).resolve().parent
arguments = argparse.ArgumentParser()
arguments.add_argument('--assert-semantic', action='store_true', help='Fail when a fixture differs from ordinary Org semantics.')
arguments.add_argument('--output-prefix', default='', help='Prefix output files, for example fixed-, to retain earlier evidence.')
args = arguments.parse_args()
if not re.fullmatch(r'[A-Za-z0-9_-]*', args.output_prefix):
    arguments.error('--output-prefix permits only letters, digits, underscores, and hyphens')
repo = here.parents[3]
out = repo / 'build/OrgSourceReview/round1/contrarian'
out.mkdir(parents=True, exist_ok=True)
vendor = repo / 'ThirdParty/TreeSitter'
common = ['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-O2', '-fblocks']
objects = []
for source in sorted((repo / 'Sources/Editor/TreeSitter').glob('NVTreeSitter*.c')):
    obj = out / (source.stem + '.o')
    subprocess.run(common + ['-std=c11', '-I', str(vendor / 'runtime/include'), '-I', str(vendor / 'runtime/src'), '-I', str(vendor / 'org/src'), '-c', str(source), '-o', str(obj)], check=True)
    objects.append(str(obj))
production = repo / 'Sources/Editor/NVSourceHighlighter.m'
subprocess.run(common + ['-I', str(repo / 'Sources/Editor'), '-framework', 'Cocoa', str(production), str(here / 'parser-probe.m')] + objects + ['-o', str(out / 'parser')], check=True)
result = subprocess.run([str(out / 'parser'), str(repo / 'Resources/Syntax')], text=True, capture_output=True, timeout=30)
(here / (args.output_prefix + 'parser-output.txt')).write_text(result.stdout + result.stderr)
print(result.stdout, end='')
print(result.stderr, end='')
result.check_returncode()
semantic_mismatches = int(re.search(r'semantic_mismatches=(\d+)', result.stdout).group(1))
link_source = repo / 'Sources/Editor/AttributedPlainText.m'
source = link_source.read_text()
methods = source[source.index('- (void)addLinkAttributesForRange:'):source.index('- (void)addStrikethroughNearDoneTagsForRange:')]
strings = (repo / 'Sources/Utilities/NSString_NV.m').read_text()
escape = strings[strings.index('- (NSString*)stringWithPercentEscapes {'):strings.index('+ (NSString*)reasonStringFromCarbonFSError:')]
generated = '''#import <Cocoa/Cocoa.h>
#import <CoreServices/CoreServices.h>
#import "AttributedPlainText.h"
@interface NSString (ProbeEscape)
- (NSString *)stringWithPercentEscapes;
@end
@implementation NSString (ProbeEscape)
''' + escape + '''\n@end
static BOOL _StringWithRangeIsProbablyObjC(NSString *string, NSRange blockRange);
@implementation NSMutableAttributedString (AttributedPlainText)
''' + methods + '\n@end\n' + (here / 'link-probe.m').read_text()
(out / 'links.m').write_text(generated)
subprocess.run(common + ['-I', str(repo / 'Sources/Editor'), '-framework', 'Cocoa', '-framework', 'CoreServices',
    '-Wno-incomplete-implementation', '-Wno-deprecated-declarations', str(out / 'links.m'), '-o', str(out / 'links')], check=True)
result = subprocess.run([str(out / 'links')], text=True, capture_output=True, timeout=30)
(here / (args.output_prefix + 'link-output.txt')).write_text(result.stdout + result.stderr)
print(result.stdout, end='')
print(result.stderr, end='')
result.check_returncode()
metadata = {'host': platform.platform(), 'architecture': 'x86_64 under Rosetta',
    'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
    'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
    'sha256': {str(path.relative_to(repo)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in [production, link_source, repo / 'ThirdParty/TreeSitter/org/src/scanner.c', repo / 'Resources/Syntax/org.scm']}}
(here / (args.output_prefix + 'metadata.json')).write_text(json.dumps(metadata, indent=2) + '\n')
if args.assert_semantic and semantic_mismatches:
    raise SystemExit(f'FAIL: {semantic_mismatches} ordinary Org semantic mismatches')
