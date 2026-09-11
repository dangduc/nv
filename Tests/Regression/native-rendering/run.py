#!/usr/bin/env python3
"""Check editor colors in a copied app with temporary notes and defaults."""
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
parser.add_argument('--app', type=Path, default=repo / 'build/DerivedData/Build/Products/Development/nvALT Development.app')
parser.add_argument('--artifacts', type=Path, help='Directory for the editor bitmap captures')
arguments = parser.parse_args()
if not arguments.app.exists():
    raise SystemExit('Build the Development app into build/DerivedData first.')
if arguments.artifacts:
    arguments.artifacts.mkdir(parents=True, exist_ok=True)

lock_path = repo / 'build/pr-review/gui.lock'
lock_path.parent.mkdir(parents=True, exist_ok=True)
with lock_path.open('w') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    with tempfile.TemporaryDirectory(prefix='nvalt-rendering-tests-') as directory:
        root = Path(directory)
        app = root / 'Rendering Tests.app'
        shutil.copytree(arguments.app, app, symlinks=True)
        info_path = app / 'Contents/Info.plist'
        info = plistlib.loads(info_path.read_bytes())
        info['CFBundleIdentifier'] = 'org.nvalt.rendering-tests.' + uuid.uuid4().hex
        info_path.write_bytes(plistlib.dumps(info))
        for name in ['Notes', 'Support', 'Temp']:
            (root / name).mkdir()
        dylib = root / 'RenderingTests.dylib'
        subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-dynamiclib',
            '-undefined', 'dynamic_lookup', '-fno-objc-arc', '-Wno-deprecated-declarations',
            *include_flags(repo), '-include', str(repo / 'Config/Notation_Prefix.pch'),
            '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(dylib),
            str(Path(__file__).with_name('probes.m'))], check=True)
        environment = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root),
                           DYLD_INSERT_LIBRARIES=str(dylib), TMPDIR=str(root / 'Temp') + '/')
        if arguments.artifacts:
            environment['NV_RENDERING_ARTIFACTS'] = str(arguments.artifacts.resolve())
        binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
        try:
            result = subprocess.run([str(binary), '-ShowDockIcon', 'YES', '-StatusBarItem', 'NO',
                '-QuitWhenClosingMainWindow', 'NO', '-SUEnableAutomaticChecks', 'NO'],
                env=environment, timeout=90)
        finally:
            subprocess.run(['/usr/bin/defaults', 'delete', info['CFBundleIdentifier']],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        raise SystemExit(result.returncode)
