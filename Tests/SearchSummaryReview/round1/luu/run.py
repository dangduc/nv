#!/usr/bin/env python3
"""Compare extracted old/new AppKit affordance geometry under the shared GUI lock."""
import fcntl
import hashlib
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[4]
here = Path(__file__).resolve().parent
out = root / 'build/SearchSummaryReview/round1/luu'
out.mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(root / 'Tests'))
from compiler_support import include_flags

source_path = 'Sources/Browser/AppController_BrowserUI.m'
def extract(text):
    start = text.index('- (void)updateSearchAffordance {')
    return text[start:text.index('\n}', start) + 2] + '\n'

old_source = subprocess.check_output(['git', 'show', '4624b3d:' + source_path], cwd=root, text=True)
new_source = (root / source_path).read_text()
old, new = extract(old_source), extract(new_source)
assert 'title matches first' not in new, 'production change is not ready'
negative = new[:-2] + '''
    // Negative control: retain the old empty 24-point strip for fuzzy queries.
    if ([[session searchMode] isEqual:@"fuzzy"] && [session hasSearchTerms]) {
        NSRect reserved = [notesSubview bounds]; reserved.size.height = MAX(0, reserved.size.height - 24);
        [notesScrollView setFrame:reserved];
    }
}
'''
variants = {'base': old, 'production': new, 'reserved_24_negative_control': negative}
record = {'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
          'base': '4624b3daf2e95a44c578d9895f65890051ed6702',
          'os': subprocess.check_output(['sw_vers'], text=True),
          'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True),
          'sourceBefore': hashlib.sha256(new_source.encode()).hexdigest(), 'variants': {}}
lock_path = root / 'build/pr-review/gui.lock'
lock_path.parent.mkdir(parents=True, exist_ok=True)
for name, method in variants.items():
    destination = out / name
    destination.mkdir(exist_ok=True)
    (destination / 'production.inc').write_text(method)
    binary = destination / 'probe'
    command = ['xcrun', 'clang', '-arch', 'arm64', '-mmacosx-version-min=11.0', '-fno-objc-arc',
        '-Wno-deprecated-declarations', '-Wno-incomplete-implementation', '-Wno-protocol',
        *include_flags(root), '-I', str(destination), '-include', str(root / 'Config/Notation_Prefix.pch'),
        str(here / 'probe.m'), '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(binary)]
    compiled = subprocess.run(command, cwd=root, text=True, capture_output=True)
    (destination / 'compile.log').write_text(compiled.stdout + compiled.stderr)
    compiled.check_returncode()
    binary_before = hashlib.sha256(binary.read_bytes()).hexdigest()
    with lock_path.open('a') as lock, (destination / 'run.log').open('w') as log:
        fcntl.flock(lock, fcntl.LOCK_EX)
        subprocess.run([str(binary), str(destination / 'result.json')], stdout=log,
                       stderr=subprocess.STDOUT, check=True, timeout=30)
    result = json.loads((destination / 'result.json').read_text())
    record['variants'][name] = {'methodSha256': hashlib.sha256(method.encode()).hexdigest(),
        'binaryBefore': binary_before, 'binaryAfter': hashlib.sha256(binary.read_bytes()).hexdigest(),
        'observations': len(result['observations']), 'newContractFailures': result['newContractFailures']}
record['sourceAfter'] = hashlib.sha256((root / source_path).read_bytes()).hexdigest()
(out / 'summary.json').write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps(record, indent=2))
assert record['sourceBefore'] == record['sourceAfter'], 'production source changed during measurement'
assert all(r['binaryBefore'] == r['binaryAfter'] for r in record['variants'].values())
assert record['variants']['production']['newContractFailures'] == 0
assert record['variants']['base']['newContractFailures'] > 0
assert record['variants']['reserved_24_negative_control']['newContractFailures'] > 0
