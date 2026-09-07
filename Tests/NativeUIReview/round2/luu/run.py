#!/usr/bin/env python3
"""Render selected rich text in an isolated, temporary nvALT app."""
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
parser.add_argument('--artifacts', type=Path, required=True)
args = parser.parse_args()
args.artifacts.mkdir(parents=True, exist_ok=True)
lock_path = repo / 'build/pr-review/gui.lock'
lock_path.parent.mkdir(parents=True, exist_ok=True)
with lock_path.open('w') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    with tempfile.TemporaryDirectory(prefix='nvalt-selection-review-') as directory:
        root = Path(directory)
        app = root / 'Selection Review.app'
        shutil.copytree(args.app, app, symlinks=True)
        info_path = app / 'Contents/Info.plist'
        info = plistlib.loads(info_path.read_bytes())
        info['CFBundleIdentifier'] = 'org.nvalt.selection-review.' + uuid.uuid4().hex
        info_path.write_bytes(plistlib.dumps(info))
        for name in ['Notes', 'Support', 'Temp']:
            (root / name).mkdir()
        dylib = root / 'SelectionReview.dylib'
        subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-dynamiclib',
            '-undefined', 'dynamic_lookup', '-fno-objc-arc', '-Wno-deprecated-declarations',
            '-I', str(repo), '-I', str(repo / 'RBSplitView'), '-I', str(repo / 'PTHotKeys'),
            '-I', str(repo / 'ODBEditor'), '-include', str(repo / 'Notation_Prefix.pch'),
            '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(dylib),
            str(Path(__file__).with_name('probes.m'))], check=True)
        environment = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root),
                           NV_LUU_ARTIFACTS=str(args.artifacts.resolve()),
                           DYLD_INSERT_LIBRARIES=str(dylib), TMPDIR=str(root / 'Temp') + '/')
        binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
        try:
            result = subprocess.run([str(binary), '-ShowDockIcon', 'YES', '-StatusBarItem', 'NO',
                '-QuitWhenClosingMainWindow', 'NO', '-SUEnableAutomaticChecks', 'NO'],
                env=environment, timeout=90)
        finally:
            subprocess.run(['/usr/bin/defaults', 'delete', info['CFBundleIdentifier']],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        raise SystemExit(result.returncode)
