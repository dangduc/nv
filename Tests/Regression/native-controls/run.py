#!/usr/bin/env python3
"""Exercise Search, Tab, and tag completion in an isolated native browser."""
import argparse
import fcntl
import os
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

parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, default=repo / 'build/DerivedData/Build/Products/Development/nvALT.app')
parser.add_argument('--probe', choices=['all', 'search', 'tab', 'tags'], default='all')
arguments = parser.parse_args()
if not arguments.app.exists():
    raise SystemExit('Build the Development app into build/DerivedData first.')
lock_path = repo / 'build/pr-review/gui.lock'
lock_path.parent.mkdir(parents=True, exist_ok=True)
with lock_path.open('w') as lock, tempfile.TemporaryDirectory(prefix='nvalt-native-controls-') as directory:
    fcntl.flock(lock, fcntl.LOCK_EX)
    root = Path(directory)
    app = root / 'Native Controls Tests.app'
    shutil.copytree(arguments.app, app, symlinks=True)
    info_path = app / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info['CFBundleIdentifier'] = 'org.nvalt.native-controls.' + uuid.uuid4().hex
    info_path.write_bytes(plistlib.dumps(info))
    for name in ['Notes', 'Support', 'Temp']:
        (root / name).mkdir()
    dylib = root / 'NativeControlsTests.dylib'
    subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-dynamiclib',
        '-undefined', 'dynamic_lookup', '-fno-objc-arc', '-Wno-deprecated-declarations',
        *include_flags(repo), '-include', str(repo / 'Config/Notation_Prefix.pch'),
        '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(dylib),
        str(Path(__file__).with_name('probes.m'))], check=True)
    environment = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root), DYLD_INSERT_LIBRARIES=str(dylib),
        NV_NATIVE_CONTROLS_PROBE=arguments.probe, TMPDIR=str(root / 'Temp') + '/')
    binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
    try:
        result = subprocess.run([str(binary), '-ShowDockIcon', 'YES', '-StatusBarItem', 'NO',
            '-QuitWhenClosingMainWindow', 'NO', '-SUEnableAutomaticChecks', 'NO'], env=environment, timeout=90)
    finally:
        subprocess.run(['defaults', 'delete', info['CFBundleIdentifier']],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    raise SystemExit(result.returncode)
