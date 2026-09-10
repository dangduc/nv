#!/usr/bin/env python3
"""Compile the production Org parser and exercise source-only behavior."""
from pathlib import Path
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parents[2]
build = root / 'build/org-source-tests'
build.mkdir(parents=True, exist_ok=True)
vendor = root / 'ThirdParty/TreeSitter'
common = ['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-std=c11', '-O2', '-fblocks']
objects = []
for source in sorted((root / 'Sources/Editor/TreeSitter').glob('NVTreeSitter*.c')):
    obj = build / (source.stem + '.o')
    subprocess.run(common + ['-I', str(vendor / 'runtime/include'), '-I', str(vendor / 'runtime/src'), '-I', str(vendor / 'org/src'), '-c', str(source), '-o', str(obj)], check=True)
    objects.append(str(obj))
subprocess.run(common + ['-I', str(root / 'Sources/Editor'), '-framework', 'Cocoa', str(root / 'Sources/Editor/NVSourceHighlighter.m'), str(Path(__file__).with_name('probe.m'))] + objects + ['-o', str(build / 'probe')], check=True)
subprocess.run([str(build / 'probe'), str(root / 'Resources/Syntax')], check=True)
manifest = json.loads((vendor / 'manifest.json').read_text())
for relative, expected in manifest['files'].items():
    if relative.startswith('org/'):
        data = (vendor / relative).read_bytes()
        assert len(data) == expected['bytes']
        assert hashlib.sha256(data).hexdigest() == expected['sha256']
query = (root / 'Resources/Syntax/org.scm').read_bytes()
assert hashlib.sha256(query).hexdigest() == manifest['queries']['Resources/Syntax/org.scm']['sha256']
print('PASS: Org manifest hashes and query hash')
