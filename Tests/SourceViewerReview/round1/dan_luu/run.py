#!/usr/bin/env python3
"""Measure production parsing separately from main-thread TextKit attributes."""
from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[4]
build = root / 'build/source-viewer-review/round1-dan-luu'
build.mkdir(parents=True, exist_ok=True)
common = ['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-std=c11', '-O2', '-fblocks']
vendor = root / 'ThirdParty/TreeSitter'
objects = []
for source in sorted((root / 'Sources/Editor/TreeSitter').glob('NVTreeSitter*.c')):
    obj = build / (source.stem + '.o')
    subprocess.run(common + ['-I', str(vendor / 'runtime/include'), '-I', str(vendor / 'runtime/src'), '-c', str(source), '-o', str(obj)], check=True)
    objects.append(str(obj))
subprocess.run(common + ['-I', str(root / 'Sources/Editor'), '-framework', 'Cocoa', str(root / 'Sources/Editor/NVSourceHighlighter.m'), str(Path(__file__).with_name('latency.m'))] + objects + ['-o', str(build / 'latency')], check=True)
result = subprocess.run([str(build / 'latency'), str(root / 'Resources/Syntax')], check=True, text=True, capture_output=True)
print(result.stdout, end='')
Path(__file__).with_name('measurements.csv').write_text(result.stdout)
