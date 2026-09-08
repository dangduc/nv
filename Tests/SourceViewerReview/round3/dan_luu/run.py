#!/usr/bin/env python3
"""Exercise the extracted production restoration method with real TextKit layout."""
from pathlib import Path
import argparse
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--negative-control', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[4]
build = root / 'build/source-viewer-review/round3-dan-luu'
build.mkdir(parents=True, exist_ok=True)
source = (root / 'Sources/Browser/AppController_Preview.m').read_text()
start = source.index('- (void)restoreSourceScroll {')
method = source[start:source.index('\n}', start)+2]
assert method.count('ensureLayoutForBoundingRect:') == 1
if args.negative_control:
    old = '[[textView layoutManager] ensureLayoutForBoundingRect:NSMakeRect(0, 0, point.x + NSWidth([textView bounds]), point.y + NSHeight([[textScrollView contentView] bounds])) inTextContainer:[textView textContainer]];'
    assert method.count(old) == 1
    method = method.replace(old, '[[textView layoutManager] ensureLayoutForTextContainer:[textView textContainer]];')
(build / 'restore_method.inc').write_text(method)
binary = build / ('viewport-mutant' if args.negative_control else 'viewport')
subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-O2', '-fblocks', '-I', str(build), '-framework', 'Cocoa', str(Path(__file__).with_name('viewport.m')), '-o', str(binary)], check=True)
result = subprocess.run([str(binary)], capture_output=True, text=True)
output = result.stdout + result.stderr
print(output, end='')
name = 'negative-control.txt' if args.negative_control else 'output.txt'
if args.negative_control:
    assert result.returncode != 0 and 'FAIL: near-top restoration avoids most document layout' in result.stderr
    output += 'PASS: probe rejects full-document-layout mutant\n'
    print('PASS: probe rejects full-document-layout mutant')
else:
    result.check_returncode()
Path(__file__).with_name(name).write_text(output)
