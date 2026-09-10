#!/usr/bin/env python3
"""Compile unchanged production highlighter and measure bounded Org workloads."""
from pathlib import Path
import hashlib
import subprocess

here = Path(__file__).resolve().parent
repo = here.parents[3]
out = repo / 'build/OrgSourceReview/round1/luu/parser'
out.mkdir(parents=True, exist_ok=True)
vendor = repo / 'ThirdParty/TreeSitter'
common = ['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-std=c11', '-O2', '-fblocks']
objects = []
for source in sorted((repo / 'Sources/Editor/TreeSitter').glob('NVTreeSitter*.c')):
    obj = out / f'{source.stem}.o'
    subprocess.run(common + ['-I', str(vendor / 'runtime/include'), '-I', str(vendor / 'runtime/src'), '-I', str(vendor / 'org/src'), '-c', str(source), '-o', str(obj)], check=True)
    objects.append(str(obj))
source = repo / 'Sources/Editor/NVSourceHighlighter.m'
subprocess.run(common + ['-I', str(repo / 'Sources/Editor'), '-framework', 'Cocoa', str(source), str(here / 'parser-probe.m')] + objects + ['-o', str(out / 'probe')], check=True)
result = subprocess.run([str(out / 'probe'), str(repo / 'Resources/Syntax')], capture_output=True, text=True, timeout=120)
output = f'NVSourceHighlighter.m SHA256: {hashlib.sha256(source.read_bytes()).hexdigest()}\n' + result.stdout + result.stderr
(here / 'parser.txt').write_text(output)
print(output)
result.check_returncode()
