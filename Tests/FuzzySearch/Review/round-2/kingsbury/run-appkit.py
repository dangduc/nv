#!/usr/bin/env python3
"""Run bounded native AppKit focus-loss, reentry, and deactivation histories."""
import fcntl
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
out = ROOT / 'build/FuzzySearchReview/round-2/kingsbury/appkit'
out.mkdir(parents=True, exist_ok=True)
groups = {
    'Sources/Browser/AppController_Search.m': ['- (BOOL)searchFieldHasFocus', '- (void)cancelTransientSearchIntents'],
    'Sources/Browser/AppController.m': ['- (void)windowDidResignKey:']
}
methods = []
spans = []
for path, signatures in groups.items():
    source = (ROOT / path).read_text()
    for signature in signatures:
        start = source.index(signature)
        method = source[start:source.index('\n}', start) + 2]
        methods.append(method)
        spans.append({'path': path, 'line': source[:start].count('\n') + 1,
                      'signature': signature, 'sha256': hashlib.sha256(method.encode()).hexdigest()})
(out / 'focus-methods.inc').write_text('\n'.join(methods))
binary = out / 'appkit-focus'
subprocess.run(['xcrun', 'clang', '-arch', 'arm64', '-fblocks', '-fno-objc-arc', '-Wno-deprecated-declarations',
                '-I' + str(out), '-framework', 'Cocoa', str(HERE / 'appkit-focus.m'), '-o', str(binary)], check=True)
lock_path = ROOT / 'build/pr-review/gui.lock'
lock_path.parent.mkdir(parents=True, exist_ok=True)
with lock_path.open('w') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
print(result.stdout, end='')
print(result.stderr, end='')
inputs = [*groups, str((HERE / 'appkit-focus.m').relative_to(ROOT)), str(Path(__file__).relative_to(ROOT))]
(HERE / 'appkit-results.json').write_text(json.dumps({
    'command': ['python3', str(Path(__file__).relative_to(ROOT))], 'exit_code': result.returncode,
    'stdout': result.stdout, 'stderr': result.stderr, 'production_methods': spans,
    'sha256': {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in inputs},
    'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
}, indent=2) + '\n')
raise SystemExit(result.returncode)
