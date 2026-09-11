#!/usr/bin/env python3
"""Compile the production link methods and check Org source decorations."""
from pathlib import Path
import subprocess

repo = Path(__file__).resolve().parents[3]
out = repo / 'build/OrgSource/Links'
out.mkdir(parents=True, exist_ok=True)
source = (repo / 'Sources/Editor/AttributedPlainText.m').read_text()
methods = source[source.index('- (void)addLinkAttributesForRange:'):source.index('- (void)addStrikethroughNearDoneTagsForRange:')]
strings = (repo / 'Sources/Utilities/NSString_NV.m').read_text()
escape = strings[strings.index('- (NSString*)stringWithPercentEscapes {'):strings.index('+ (NSString*)reasonStringFromCarbonFSError:')]
code = '''#import <Cocoa/Cocoa.h>
#import <CoreServices/CoreServices.h>
#import "AttributedPlainText.h"
#import "../Application/NVAppIdentity.h"
@interface NSString (ProbeEscape)
- (NSString *)stringWithPercentEscapes;
@end
@implementation NSString (ProbeEscape)
''' + escape + '''\n@end
static BOOL _StringWithRangeIsProbablyObjC(NSString *string, NSRange blockRange);
@implementation NSMutableAttributedString (AttributedPlainText)
''' + methods + '\n@end\n' + (Path(__file__).parent / 'probe.m').read_text()
(out / 'probe.m').write_text(code)
subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-fblocks',
    '-framework', 'Cocoa', '-framework', 'CoreServices', '-Wno-deprecated-declarations',
    '-Wno-incomplete-implementation', '-I', str(repo / 'Sources/Editor'),
    str(out / 'probe.m'), '-o', str(out / 'probe')], check=True)
result = subprocess.run([str(out / 'probe')], text=True, capture_output=True)
print(result.stdout, end='')
print(result.stderr, end='')
(out / 'output.txt').write_text(result.stdout + result.stderr)
raise SystemExit(result.returncode)
