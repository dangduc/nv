#!/usr/bin/env python3
"""Confirm key-window focus semantics using actual AppKit controls, arm64 only."""
import fcntl
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
out = ROOT / 'build/FuzzySearchReview/round-1/kingsbury/appkit'
out.mkdir(parents=True, exist_ok=True)
production = ROOT / 'Sources/Browser/AppController_Search.m'
source = production.read_text()
start = source.index('- (BOOL)searchFieldHasFocus')
method = source[start:source.index('\n}', start) + 2]
(out / 'focus-method.inc').write_text(method + '\n')
binary = out / 'appkit-focus'
subprocess.run(['xcrun', 'clang', '-arch', 'arm64', '-fno-objc-arc', '-Wno-deprecated-declarations',
                '-I' + str(out), '-framework', 'Cocoa', str(HERE / 'appkit-focus.m'), '-o', str(binary)], check=True)
lock_path = ROOT / 'build/pr-review/gui.lock'
lock_path.parent.mkdir(parents=True, exist_ok=True)
with lock_path.open('w') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
print(result.stdout, end='')
print(result.stderr, end='')
(HERE / 'appkit-results.json').write_text(json.dumps({
    'command': ['python3', str(Path(__file__).relative_to(ROOT))], 'exit_code': result.returncode,
    'stdout': result.stdout, 'stderr': result.stderr,
    'production_method_sha256': hashlib.sha256(method.encode()).hexdigest(),
    'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
}, indent=2) + '\n')
raise SystemExit(result.returncode)
