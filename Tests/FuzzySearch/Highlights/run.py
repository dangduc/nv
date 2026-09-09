#!/usr/bin/env python3
"""Exercise the production shared-source highlight invalidation callback."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
p = argparse.ArgumentParser()
p.add_argument('--arch', choices=['arm64', 'x86_64'])
p.add_argument('--sanitize', action='store_true')
p.add_argument('--build-only', action='store_true')
a = p.parse_args()
out = ROOT / 'build/FuzzySearchHighlightTests'
out.mkdir(parents=True, exist_ok=True)
source = (ROOT / 'Sources/Browser/AppController_Search.m').read_text()
start = source.index('- (void)searchSourceStorageWillProcessEditing:')
method = source[start:source.index('- (void)refreshSearchHighlights', start)]
(out / 'callback.inc').write_text(method)
binary = out / ('highlights-' + (a.arch or 'native') + ('-sanitize' if a.sanitize else ''))
flags = ['-fno-objc-arc', '-Wall', '-Wextra', '-Werror', '-g', '-O1', '-I' + str(out)]
if a.arch:
    flags += ['-arch', a.arch, '-mmacosx-version-min=10.13' if a.arch == 'x86_64' else '-mmacosx-version-min=11.0']
if a.sanitize:
    flags += ['-fsanitize=address,undefined', '-fno-omit-frame-pointer']
subprocess.run(['xcrun', 'clang', *flags, str(HERE / 'probe.m'), '-framework', 'Cocoa', '-o', str(binary)], check=True)
if not a.build_only:
    subprocess.run([str(binary)], check=True, timeout=30)
