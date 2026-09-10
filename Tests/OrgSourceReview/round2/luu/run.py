#!/usr/bin/env python3
"""Build independent Round 2 probes against the current production sources."""
from pathlib import Path
import hashlib
import json
import platform
import subprocess

here = Path(__file__).resolve().parent
repo = here.parents[3]
out = repo / 'build/OrgSourceReview/round2/luu'
out.mkdir(parents=True, exist_ok=True)
vendor = repo / 'ThirdParty/TreeSitter'
common = ['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-O2', '-std=c11', '-fblocks']
include = ['-I', str(repo), '-I', str(repo / 'Sources/Editor'), '-I', str(vendor / 'runtime/include'),
           '-I', str(vendor / 'runtime/src'), '-I', str(vendor / 'org/src')]
objects = []
for source in sorted((repo / 'Sources/Editor/TreeSitter').glob('NVTreeSitter*.c')):
    obj = out / f'{source.stem}.o'
    subprocess.run(common + include + ['-c', str(source), '-o', str(obj)], check=True)
    objects.append(str(obj))

link_source = (repo / 'Sources/Editor/AttributedPlainText.m').read_text()
methods = link_source[link_source.index('- (void)addLinkAttributesForRange:'):link_source.index('- (void)addStrikethroughNearDoneTagsForRange:')]
strings = (repo / 'Sources/Utilities/NSString_NV.m').read_text()
escape = strings[strings.index('- (NSString*)stringWithPercentEscapes {'):strings.index('+ (NSString*)reasonStringFromCarbonFSError:')]
prefix = '#import <Cocoa/Cocoa.h>\n#import <CoreServices/CoreServices.h>\n#import "AttributedPlainText.h"\n'
prefix += '@interface NSString (ProbeEscape)\n- (NSString *)stringWithPercentEscapes;\n@end\n@implementation NSString (ProbeEscape)\n'
prefix += escape + '\n@end\nstatic BOOL _StringWithRangeIsProbablyObjC(NSString *string, NSRange blockRange);\n'
link_generated = out / 'link.m'
link_generated.write_text(prefix + '@implementation NSMutableAttributedString (AttributedPlainText)\n' + methods + '\n@end\n' + (here / 'links.m').read_text())

programs = [
    ('parser', [str(here / 'parser.m')] + objects + ['-framework', 'Cocoa'], [str(repo / 'Resources/Syntax')]),
    ('links', [str(link_generated), '-framework', 'Cocoa', '-framework', 'CoreServices', '-Wno-incomplete-implementation', '-Wno-deprecated-declarations'], []),
    ('scanner', [str(here / 'scanner.c')], []),
]
for name, sources, args in programs:
    binary = out / name
    subprocess.run(common + include + sources + ['-o', str(binary)], check=True)
    result = subprocess.run([str(binary)] + args, capture_output=True, text=True, timeout=180)
    (here / f'{name}-output.txt').write_text(result.stdout + result.stderr)
    print(name + '\n' + result.stdout + result.stderr)
    result.check_returncode()

paths = ['Sources/Editor/NVSourceHighlighter.m', 'Sources/Editor/AttributedPlainText.m',
         'ThirdParty/TreeSitter/org/src/scanner.c', 'Resources/Syntax/org.scm']
metadata = {
    'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
    'host': platform.platform(),
    'execution': 'x86_64 under Rosetta, macOS 10.13 deployment target',
    'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
    'sha256': {path: hashlib.sha256((repo / path).read_bytes()).hexdigest() for path in paths},
    'scope': 'Production highlighter imported unchanged. Link methods extracted unchanged. Scanner imported unchanged with ordinary valid states only.'
}
(here / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
