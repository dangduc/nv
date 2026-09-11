#!/usr/bin/env python3
"""Run an independent review probe in a copied app with disposable notes."""
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

repo = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(repo / 'Tests'))
from compiler_support import include_flags

parser = argparse.ArgumentParser()
parser.add_argument('--probe', type=Path, required=True)
parser.add_argument('--prefix', type=Path)
parser.add_argument('--app', type=Path, default=repo / 'build/DerivedData/Build/Products/Development/nvALT Development.app')
parser.add_argument('--launches', type=int, default=1)
parser.add_argument('--timeout', type=float, default=120)
parser.add_argument('--launch-arg', action='append', default=[])
args = parser.parse_args()
lock_path = repo / 'build/pr-review/gui.lock'
lock_path.parent.mkdir(parents=True, exist_ok=True)
with lock_path.open('w') as lock, tempfile.TemporaryDirectory(prefix='nvalt-view-review-') as directory:
    fcntl.flock(lock, fcntl.LOCK_EX)
    root = Path(directory)
    app = root / 'View Review.app'
    shutil.copytree(args.app, app, symlinks=True)
    info_path = app / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info['CFBundleIdentifier'] = 'org.nvalt.view-review.' + uuid.uuid4().hex
    info_path.write_bytes(plistlib.dumps(info))
    for name in ['Notes', 'Support', 'Temp']:
        (root / name).mkdir()
    base = (repo / 'Tests/Regression/native-controls/probes.m').read_text()
    helpers = (repo / 'Tests/Regression/native-controls/checks.inc').read_text().split('- (void)nv_focusSearch {')[0]
    base = base.replace('[self setupViewsAfterAppAwakened];', 'unsetenv("DYLD_INSERT_LIBRARIES"); [self setupViewsAfterAppAwakened];')
    base = base.replace('#include "checks.inc"', helpers + '\n' + args.probe.read_text())
    prefix = args.prefix.read_text() if args.prefix else ''
    harness = root / 'Review.m'
    harness.write_text(prefix + '\n' + base)
    dylib = root / 'ViewReview.dylib'
    subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-dynamiclib',
        '-undefined', 'dynamic_lookup', '-fno-objc-arc', '-Wno-deprecated-declarations',
        *include_flags(repo), '-I', str(args.probe.resolve().parent),
        '-include', str(repo / 'Config/Notation_Prefix.pch'), '-framework', 'Cocoa',
        '-framework', 'Carbon', '-framework', 'WebKit', '-o', str(dylib), str(harness)], check=True)
    env = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root), DYLD_INSERT_LIBRARIES=str(dylib),
        TMPDIR=str(root / 'Temp') + '/')
    binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
    try:
        for phase in range(1, args.launches + 1):
            env['NV_REVIEW_PHASE'] = str(phase)
            result = subprocess.run([str(binary), '-ShowDockIcon', 'YES', '-StatusBarItem', 'NO',
                '-QuitWhenClosingMainWindow', 'NO', '-SUEnableAutomaticChecks', 'NO',
                *args.launch_arg], env=env, timeout=args.timeout)
            if result.returncode:
                raise SystemExit(result.returncode)
    finally:
        subprocess.run(['defaults', 'delete', info['CFBundleIdentifier']],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
