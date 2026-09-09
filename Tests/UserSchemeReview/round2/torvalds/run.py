#!/usr/bin/env python3
"""Check editor helper availability, then run modern and forced-fallback native probes."""
from pathlib import Path
import subprocess
import sys
import tempfile

here = Path(__file__).resolve().parent
root = here.parents[3]
sys.path.insert(0, str(root / 'Tests'))
from compiler_support import include_flags

source = (root / 'Sources/Editor/LinkingEditor.m').read_text()
start = source.index('- (NSDictionary *)currentSearchHighlightAttributes {')
method = source[start:source.index('\n}', start) + 2]
modern = 'if (@available(macOS 11.0, *)) [[self effectiveAppearance] performAsCurrentDrawingAppearance:resolve];'
if method.count(modern) != 1:
    raise SystemExit('FAIL: expected a macOS 11 guard around editor drawing appearance')
renamed = method.replace('currentSearchHighlightAttributes {', 'nv_reviewFallbackHighlightAttributes {')
prefix = (here / 'prefix.h').read_text()
with tempfile.TemporaryDirectory(prefix='nvalt-torvalds-editor-') as directory:
    output = Path(directory)
    original = output / 'Original.m'
    original.write_text(prefix + '\n@implementation LinkingEditor (NVExtractedCompatibility)\n' + renamed + '\n@end\n')
    subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-fsyntax-only',
        '-fno-objc-arc', '-Werror=unguarded-availability-new', '-Wno-deprecated-declarations',
        '-Wno-undefined-internal', *include_flags(root), '-include', str(root / 'Config/Notation_Prefix.pch'),
        str(original)], check=True)
    print('PASS: unchanged production helper compiles with availability errors enabled for macOS 10.13', flush=True)
    forced = renamed.replace(modern, 'if (NO) { }')
    generated = output / 'prefix.h'
    generated.write_text(prefix + '\n@implementation LinkingEditor (NVExtractedCompatibility)\n' + forced + '\n@end\n')
    subprocess.run(['python3', str(root / 'Tests/ViewControlsReview/run-probe.py'),
        '--probe', str(here / 'probe.inc'), '--prefix', str(generated)], check=True)
