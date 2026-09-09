#!/usr/bin/env python3
"""Build or run a production-app search probe using disposable notes and defaults."""
import argparse
import fcntl
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'Tests'))
from compiler_support import include_flags

parser = argparse.ArgumentParser()
parser.add_argument('--build-only', action='store_true', help='Compile the injected probe without starting an Intel process.')
parser.add_argument('--timeout', type=float, default=60, help='Disposable app timeout in seconds.')
a = parser.parse_args()
output = ROOT / 'build/FuzzySearchUI'
output.mkdir(parents=True, exist_ok=True)
base = (ROOT / 'Tests/MultipleWindowsTests.m').read_text()
prefix = base.split('- (void)nv_runTests {')[0] + '- (void)nv_runTests {'
prefix = prefix.replace('[self setupViewsAfterAppAwakened];', '''Check([[[NSBundle mainBundle] bundleIdentifier] hasPrefix:@"org.nvalt.window-tests."], @"isolated copied-app preferences domain");
    Check([[[NSBundle mainBundle] bundlePath] hasPrefix:[TestDirectory stringByAppendingString:@"/"]], @"copied app belongs to temporary test root");
    [self setupViewsAfterAppAwakened];''')
harness = output / 'FuzzySearchProbe.m'
harness.write_text((HERE / 'support.h').read_text() + prefix + (HERE / 'probe-body.m').read_text())
dylib = output / 'FuzzySearchProbe.dylib'
subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-dynamiclib', '-undefined', 'dynamic_lookup', '-fblocks', '-fno-objc-arc', '-Wno-deprecated-declarations', *include_flags(ROOT), '-include', str(ROOT / 'Config/Notation_Prefix.pch'), '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(dylib), str(harness)], check=True)
print(f'BUILT: {dylib}', flush=True)
if a.build_only:
    raise SystemExit(0)
source = ROOT / 'build/DerivedData/Build/Products/Development/nvALT.app'
if not source.exists():
    raise SystemExit('Build the Development app into build/DerivedData first.')
lock_path = ROOT / 'build/pr-review/gui.lock'
lock_path.parent.mkdir(parents=True, exist_ok=True)
lock = lock_path.open('w')
try:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    raise SystemExit('Another desktop test owns the GUI lock. The probe was built but not run.')
with tempfile.TemporaryDirectory(prefix='nvalt-fuzzy-ui-') as temporary:
    root = Path(temporary)
    app = root / 'Fuzzy Search Tests.app'
    shutil.copytree(source, app, symlinks=True)
    path = app / 'Contents/Info.plist'
    info = plistlib.loads(path.read_bytes())
    info['CFBundleIdentifier'] = 'org.nvalt.window-tests.' + uuid.uuid4().hex
    path.write_bytes(plistlib.dumps(info))
    for directory in ('Notes', 'Support', 'Temp'):
        (root / directory).mkdir()
    environment = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root), DYLD_INSERT_LIBRARIES=str(dylib), TMPDIR=str(root/'Temp') + '/')
    binary = app/'Contents/MacOS'/info['CFBundleExecutable']
    process = subprocess.Popen([str(binary), '-ShowDockIcon', 'YES', '-StatusBarItem', 'NO', '-QuitWhenClosingMainWindow', 'NO'], env=environment)
    try:
        code = process.wait(timeout=a.timeout)
    except subprocess.TimeoutExpired:
        process.kill()
        # A stalled Rosetta task can ignore SIGKILL in kernel U state. Never
        # perform an unbounded reap while holding the shared desktop lock.
        raise SystemExit(f'No completed app result within {a.timeout:g}s; kill sent to disposable PID {process.pid}.')
    raise SystemExit(code)
