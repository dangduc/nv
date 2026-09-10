#!/usr/bin/env python3
"""Compile and test the pinned native syntax parsers without launching the app."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[3]
build = root / 'build/source-highlighting'
build.mkdir(parents=True, exist_ok=True)
common = ['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-std=c11', '-O2', '-fblocks']
vendor = root / 'ThirdParty/TreeSitter'
units = [(source.stem, source) for source in sorted((root / 'Sources/Editor/TreeSitter').glob('NVTreeSitter*.c'))]
for name, source in units:
    subprocess.run(common + ['-I', str(vendor / 'runtime/include'), '-I', str(vendor / 'org/src'), '-I', str(vendor / 'runtime/src'), '-c', str(source), '-o', str(build / (name + '.o'))], check=True)
subprocess.run(common + ['-I', str(root / 'Sources/Editor'), '-framework', 'Cocoa', str(root / 'Sources/Editor/NVSourceHighlighter.m'), str(Path(__file__).with_name('probe.m'))] + [str(build / (name + '.o')) for name, _ in units] + ['-o', str(build / 'probe')], check=True)
subprocess.run([str(build / 'probe'), str(root / 'Resources/Syntax')], check=True)
