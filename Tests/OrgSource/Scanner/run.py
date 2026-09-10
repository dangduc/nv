#!/usr/bin/env python3
"""Check the locally patched scanner contract; never compile unpatched code."""
from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[3]
here = Path(__file__).resolve().parent
build = root / 'build/org-scanner-tests'
build.mkdir(parents=True, exist_ok=True)
vendor = root / 'ThirdParty/TreeSitter'
base = ['xcrun', 'clang', '-std=c11', '-O2', '-fblocks']
includes = ['-I', str(vendor / 'runtime/include'), '-I', str(vendor / 'runtime/src'), '-I', str(vendor / 'org/src')]
for arch, minimum, sanitized in [('x86_64', '10.13', False), ('arm64', '11.0', False), ('arm64', '11.0', True)]:
    label = arch + ('-sanitized' if sanitized else '')
    binary = build / ('state-' + label)
    flags = ['-fsanitize=address,undefined', '-fno-omit-frame-pointer'] if sanitized else []
    subprocess.run(base + ['-arch', arch, '-mmacosx-version-min=' + minimum] + flags + includes + [str(here / 'state.c'), '-o', str(binary)], check=True)
    print(label, flush=True)
    subprocess.run([str(binary)], check=True)
common = base + ['-arch', 'x86_64', '-mmacosx-version-min=10.13']
objects = []
for source in sorted((root / 'Sources/Editor/TreeSitter').glob('NVTreeSitter*.c')):
    obj = build / (source.stem + '.o')
    subprocess.run(common + includes + ['-c', str(source), '-o', str(obj)], check=True)
    objects.append(str(obj))
source_obj = build / 'NVSourceHighlighter.o'
subprocess.run(common + ['-I', str(root / 'Sources/Editor'), '-Dts_parser_parse_with_options=NVScannerProbeParse', '-c', str(root / 'Sources/Editor/NVSourceHighlighter.m'), '-o', str(source_obj)], check=True)
subprocess.run(common + includes + ['-I', str(root / 'Sources/Editor'), '-framework', 'Cocoa', str(here / 'adapter.m'), str(source_obj)] + objects + ['-o', str(build / 'adapter')], check=True)
subprocess.run([str(build / 'adapter'), str(root / 'Resources/Syntax')], check=True)
