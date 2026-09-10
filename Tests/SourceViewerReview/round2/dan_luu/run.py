#!/usr/bin/env python3
"""Measure the production display bound with independent boundary fixtures."""
from pathlib import Path
import argparse
import subprocess

options = argparse.ArgumentParser()
options.add_argument('--negative-control', action='store_true',
                     help='Verify that the fixture rejects a doubled display budget.')
args = options.parse_args()
root = Path(__file__).resolve().parents[4]
build = root / 'build/source-viewer-review/round2-dan-luu'
build.mkdir(parents=True, exist_ok=True)
common = ['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13',
          '-std=c11', '-O2', '-fblocks']
vendor = root / 'ThirdParty/TreeSitter'
objects = []
for source in sorted((root / 'Sources/Editor/TreeSitter').glob('NVTreeSitter*.c')):
    obj = build / (source.stem + '.o')
    subprocess.run(common + ['-I', str(vendor / 'runtime/include'), '-I', str(vendor / 'org/src'), '-I',
                            str(vendor / 'runtime/src'), '-c', str(source),
                            '-o', str(obj)], check=True)
    objects.append(str(obj))
highlighter = root / 'Sources/Editor/NVSourceHighlighter.m'
binary = build / 'boundary'
if args.negative_control:
    text = highlighter.read_text()
    old = 'NVSourceMaximumDisplayOperations = 4096;'
    assert text.count(old) == 1
    text = text.replace(old, 'NVSourceMaximumDisplayOperations = 8192;')
    text = text.replace('../../ThirdParty/TreeSitter/runtime/include/tree_sitter/api.h',
                        str(vendor / 'runtime/include/tree_sitter/api.h'))
    highlighter = build / 'mutant-highlighter.m'
    highlighter.write_text(text)
    binary = build / 'boundary-mutant'
subprocess.run(common + ['-I', str(root / 'Sources/Editor'), '-framework', 'Cocoa',
                        str(highlighter),
                        str(Path(__file__).with_name('boundary.m'))] + objects +
               ['-o', str(binary)], check=True)
result = subprocess.run([str(binary), str(root / 'Resources/Syntax')],
                        text=True, capture_output=True)
print(result.stdout, end='')
print(result.stderr, end='')
name = 'negative-control.txt' if args.negative_control else 'output.txt'
Path(__file__).with_name(name).write_text(result.stdout + result.stderr)
if args.negative_control:
    assert result.returncode != 0
    assert 'FAIL: first application independently bounded' in result.stderr
    print('PASS: fixture rejects the doubled-budget mutant')
else:
    result.check_returncode()
