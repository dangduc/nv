#!/usr/bin/env python3
"""Compile an independent source-highlighter review probe with pinned grammars."""
import argparse
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--probe', type=Path, required=True)
parser.add_argument('--implementation', type=Path, default=root / 'Sources/Editor/NVSourceHighlighter.m')
args = parser.parse_args()
probe = args.probe.resolve()
build = root / 'build/SyntaxFlickerReview' / probe.parent.relative_to(Path(__file__).resolve().parent)
build.mkdir(parents=True, exist_ok=True)
common = ['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-std=c11', '-O2', '-fblocks']
vendor = root / 'ThirdParty/TreeSitter'
objects = []
for source in sorted((root / 'Sources/Editor/TreeSitter').glob('NVTreeSitter*.c')):
    target = build / (source.stem + '.o')
    subprocess.run(common + ['-I', str(vendor / 'runtime/include'), '-I', str(vendor / 'runtime/src'),
                            '-c', str(source), '-o', str(target)], check=True)
    objects.append(str(target))
binary = build / 'probe'
subprocess.run(common + ['-I', str(root / 'Sources/Editor'), '-framework', 'Cocoa',
                        str(args.implementation.resolve()), str(probe), *objects, '-o', str(binary)], check=True)
subprocess.run([str(binary), str(root / 'Resources/Syntax')], check=True, timeout=120)
