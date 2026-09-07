#!/usr/bin/env python3
"""Check interleaved metadata and filtered-note histories in two windows."""
import argparse
import fcntl
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

repo = Path(__file__).resolve().parents[4]
parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, default=repo / 'build/DerivedData/Build/Products/Development/nvALT.app')
arguments = parser.parse_args()
if not arguments.app.exists():
    raise SystemExit('Build the Development app into build/DerivedData first.')
lock_path = repo / 'build/pr-review/gui.lock'
lock_path.parent.mkdir(parents=True, exist_ok=True)
with lock_path.open('w') as lock, tempfile.TemporaryDirectory(prefix='nvalt-r2-kingsbury-') as directory:
    fcntl.flock(lock, fcntl.LOCK_EX)
    root = Path(directory)
    app = root / 'Native Controls Tests.app'
    shutil.copytree(arguments.app, app, symlinks=True)
    info_path = app / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info['CFBundleIdentifier'] = 'org.nvalt.r2-kingsbury.' + uuid.uuid4().hex
    info_path.write_bytes(plistlib.dumps(info))
    for name in ['Notes', 'Support', 'Temp']:
        (root / name).mkdir()
    dylib = root / 'NativeControlsTests.dylib'
    subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-dynamiclib',
        '-undefined', 'dynamic_lookup', '-fno-objc-arc', '-Wno-deprecated-declarations',
        '-I', str(repo), '-I', str(repo / 'RBSplitView'), '-I', str(repo / 'PTHotKeys'),
        '-I', str(repo / 'ODBEditor'), '-include', str(repo / 'Notation_Prefix.pch'),
        '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(dylib),
        str(Path(__file__).with_name('probes.m'))], check=True)
    environment = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root), DYLD_INSERT_LIBRARIES=str(dylib),
        TMPDIR=str(root / 'Temp') + '/')
    binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
    try:
        output = root / 'probe.log'
        launch = ['open', '-W', '-n', '--stdout', str(output), '--stderr', str(output)]
        for key in ['NV_WINDOW_TEST_DIRECTORY', 'DYLD_INSERT_LIBRARIES', 'TMPDIR']:
            launch.extend(['--env', key + '=' + environment[key]])
        result = subprocess.run(launch + [str(app), '--args', '-ShowDockIcon', 'YES', '-StatusBarItem', 'NO',
            '-QuitWhenClosingMainWindow', 'NO', '-SUEnableAutomaticChecks', 'NO'], timeout=90)
        log = output.read_text() if output.exists() else ''
        print(log, end='')
        passed = result.returncode == 0 and 'KINGSBURY ROUND 2 PASSED' in log
    finally:
        subprocess.run(['defaults', 'delete', info['CFBundleIdentifier']],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    raise SystemExit(0 if passed else 1)
