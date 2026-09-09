#!/usr/bin/env python3
"""Build native AppKit measurement and direct-field negative control; lock GUI."""
from pathlib import Path
import fcntl
import hashlib
import json
import platform
import statistics
import subprocess
import sys

root = Path(__file__).resolve().parents[4]
here = Path(__file__).resolve().parent
out = root / 'build/TitlebarReview/round1/luu'
out.mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(root / 'Tests'))
from compiler_support import include_flags

def extract(path, prefix):
    source = (root / path).read_text()
    start = source.index(prefix)
    return source[start:source.index('\n}', start) + 2]

paths = ['Sources/Browser/AppController_BrowserUI.m', 'Sources/Browser/AppController.m', 'Sources/UI/DualField.m']
methods = [extract(paths[0], prefix) for prefix in [
    '- (void)setDualFieldInToolbar {', '- (NSArray *)toolbarDefaultItemIdentifiers:',
    '- (NSArray *)toolbarAllowedItemIdentifiers:', '- (NSToolbarItem *)toolbar:',
]] + [extract(paths[1], '- (void)selectSearchField {')]
production = '\n\n'.join(methods) + '\n'
start = production.index('    // Let the container expand')
end = production.index('    [dualFieldItem setMinSize', start)
negative = production[:start] + '    [field setAutoresizingMask:NSViewWidthSizable];\n    [dualFieldItem setView:field];\n' + production[end:]

record = {'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
    'machine': platform.machine(), 'source_sha256': {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in paths},
    'extracted_methods_sha256': hashlib.sha256(production.encode()).hexdigest(), 'variants': {}}
(root / 'build/pr-review').mkdir(parents=True, exist_ok=True)
for name, text in [('production', production), ('direct_field_negative_control', negative)]:
    destination = out / name
    destination.mkdir(exist_ok=True)
    (destination / 'production.inc').write_text(text)
    binary = destination / 'probe'
    command = ['xcrun', 'clang', '-arch', 'arm64', '-mmacosx-version-min=11.0', '-fno-objc-arc',
        '-Wno-deprecated-declarations', '-Wno-incomplete-implementation', '-Wno-protocol',
        *include_flags(root), '-I', str(destination), '-include', str(root / 'Config/Notation_Prefix.pch'),
        str(here / 'probe.m'), str(root / paths[2]), '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(binary)]
    compiled = subprocess.run(command, text=True, capture_output=True)
    (destination / 'compile.log').write_text(compiled.stdout + compiled.stderr)
    compiled.check_returncode()
    with (root / 'build/pr-review/gui.lock').open('a') as lock, (destination / 'run.log').open('w') as log:
        fcntl.flock(lock, fcntl.LOCK_EX)
        subprocess.run([str(binary), str(destination / 'result.json')], stdout=log, stderr=subprocess.STDOUT,
            check=True, timeout=30)
    result = json.loads((destination / 'result.json').read_text())
    timing = sorted(result['resizePlusLayoutMilliseconds'])
    record['variants'][name] = {'geometryFailures': result['geometryFailures'],
        'geometryChecks': len(result['geometry']), 'resizePlusLayoutMilliseconds': {
            'samples': len(timing), 'median': statistics.median(timing), 'p95': timing[int(.95 * (len(timing) - 1))],
            'max': max(timing)}}
(out / 'summary.json').write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps(record, indent=2))
assert record['variants']['production']['geometryFailures'] == 0
assert record['variants']['direct_field_negative_control']['geometryFailures'] > 0
