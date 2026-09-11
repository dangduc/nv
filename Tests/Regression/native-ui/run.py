#!/usr/bin/env python3
"""Run Cocoa integration tests in a copied app with temporary notes and defaults."""
import os
import argparse
import fcntl
from pathlib import Path
import sys
import plistlib
import shutil
import subprocess
import tempfile
import uuid

repo = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags

lock_path = repo / 'build/pr-review/gui.lock'
lock_path.parent.mkdir(parents=True, exist_ok=True)
lock = lock_path.open('w')
fcntl.flock(lock, fcntl.LOCK_EX)
parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, default=repo / 'build/DerivedData/Build/Products/Development/nvALT Development.app')
parser.add_argument('--benchmark', action='store_true')
arguments = parser.parse_args()
source = arguments.app
if not source.exists():
    raise SystemExit('Build the Development app into build/DerivedData first.')
with tempfile.TemporaryDirectory(prefix='nvalt-window-tests-') as root:
    root = Path(root)
    app = root / 'Window Tests.app'
    shutil.copytree(source, app, symlinks=True)
    info_path = app / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info['CFBundleIdentifier'] = 'org.nvalt.window-tests.' + uuid.uuid4().hex
    info_path.write_bytes(plistlib.dumps(info))
    (root / 'Notes').mkdir()
    (root / 'Support').mkdir()
    (root / 'Temp').mkdir()
    dylib = root / 'WindowTests.dylib'
    subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-dynamiclib',
        '-undefined', 'dynamic_lookup', '-fno-objc-arc', '-Wno-deprecated-declarations',
        *include_flags(repo), '-include', str(repo / 'Config/Notation_Prefix.pch'),
        '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(dylib),
        str(Path(__file__).with_name('benchmark.m' if arguments.benchmark else 'probes.m'))], check=True)
    environment = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root), DYLD_INSERT_LIBRARIES=str(dylib), TMPDIR=str(root / 'Temp') + '/')
    binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
    arguments = [str(binary), '-ShowDockIcon', 'YES', '-StatusBarItem', 'NO',
        '-QuitWhenClosingMainWindow', 'NO', '-SUEnableAutomaticChecks', 'NO']
    if os.environ.get('NV_WINDOW_TEST_DEBUG'):
        debug_env = ' '.join(key + '=' + str(environment[key]) for key in ['NV_WINDOW_TEST_DIRECTORY', 'DYLD_INSERT_LIBRARIES'])
        raise SystemExit(subprocess.run(['xcrun', 'lldb', '--batch', '-o', 'settings set target.env-vars ' + debug_env,
            '-o', 'run', '-k', 'thread backtrace', '-k', 'register read rdi rsi', '-o', 'quit', '--', *arguments], timeout=90).returncode)
    if os.environ.get('NV_UI_FULL_SCREEN'):
        # Launch Services gives the fullscreen test a foreground application.
        # A direct executable launch can remain inactive despite activate calls.
        output = root / 'fullscreen.log'
        launch = ['open', '-W', '-n', '--stdout', str(output), '--stderr', str(output)]
        for key in ['NV_WINDOW_TEST_DIRECTORY', 'DYLD_INSERT_LIBRARIES', 'TMPDIR', 'NV_UI_FULL_SCREEN', 'NV_UI_ARTIFACTS']:
            if key in environment:
                launch.extend(['--env', key + '=' + environment[key]])
        result = subprocess.run(launch + [str(app), '--args', *arguments[1:]], timeout=90)
        log = output.read_text() if output.exists() else ''
        print(log, end='')
        raise SystemExit(0 if result.returncode == 0 and 'NATIVE UI TESTS PASSED' in log else 1)
    result = subprocess.run(arguments, env=environment, timeout=90)
    if result.returncode:
        raise SystemExit(result.returncode)
    raise SystemExit(result.returncode)
