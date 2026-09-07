#!/usr/bin/env python3
"""Check pending metadata and toolbar recovery across two isolated app launches."""
import argparse
import fcntl
from pathlib import Path
import plistlib
import re
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
with lock_path.open('w') as lock, tempfile.TemporaryDirectory(prefix='nvalt-r3-torvalds-') as directory:
    fcntl.flock(lock, fcntl.LOCK_EX)
    root = Path(directory)
    app = root / 'Round 3 Toolbar Tests.app'
    shutil.copytree(arguments.app, app, symlinks=True)
    info_path = app / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info['CFBundleIdentifier'] = 'org.nvalt.r3-torvalds.' + uuid.uuid4().hex
    info_path.write_bytes(plistlib.dumps(info))
    for name in ['Notes', 'Support', 'Temp']:
        (root / name).mkdir()
    dylib = root / 'ToolbarTests.dylib'
    subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-dynamiclib',
        '-undefined', 'dynamic_lookup', '-fno-objc-arc', '-Wno-deprecated-declarations',
        '-I', str(repo), '-I', str(repo / 'RBSplitView'), '-I', str(repo / 'PTHotKeys'),
        '-I', str(repo / 'ODBEditor'), '-include', str(repo / 'Notation_Prefix.pch'),
        '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(dylib),
        str(Path(__file__).with_name('probes.m'))], check=True)
    binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
    try:
        for phase in ['1', '2']:
            output = root / ('phase-' + phase + '.log')
            launch = ['open', '-W', '-n', '--stdout', str(output), '--stderr', str(output)]
            for key, value in {
                'NV_WINDOW_TEST_DIRECTORY': str(root), 'DYLD_INSERT_LIBRARIES': str(dylib),
                'TMPDIR': str(root / 'Temp') + '/', 'NV_REVIEW_PHASE': phase,
            }.items():
                launch.extend(['--env', key + '=' + value])
            try:
                result = subprocess.run(launch + [str(app), '--args', '-ShowDockIcon', 'YES',
                    '-StatusBarItem', 'NO', '-QuitWhenClosingMainWindow', 'NO',
                    '-SUEnableAutomaticChecks', 'NO'], timeout=90)
            except subprocess.TimeoutExpired:
                subprocess.run(['pkill', '-f', re.escape(str(binary))], check=False)
                raise SystemExit('Timed out after 90 seconds; terminated only the copied app.')
            finally:
                log = output.read_text() if output.exists() else ''
                print(log, end='', flush=True)
            if result.returncode or ('ROUND 3 TORVALDS PHASE ' + phase + ' PASSED') not in log:
                raise SystemExit(1)
    finally:
        subprocess.run(['defaults', 'delete', info['CFBundleIdentifier']],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
