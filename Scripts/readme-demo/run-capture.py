#!/usr/bin/env python3
"""Record the README demo in a copied app with disposable notes."""
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
from desktop_test_support import require_clean_desktop, run_desktop_process

source = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, default=repo / 'build/DerivedData/Build/Products/Development/Neo Notational V Development.app')
parser.add_argument('--output', type=Path, default=repo / 'build/readme-demo')
parser.add_argument('--timeout', type=float, default=120)
args = parser.parse_args()
args.app = args.app.expanduser().resolve()
args.output = args.output.expanduser().resolve()
if not (args.app / 'Contents/Info.plist').is_file():
    parser.error(f'Build the Development app first, or supply --app: {args.app}')
lock_path = repo / 'build/pr-review/gui.lock'
lock_path.parent.mkdir(parents=True, exist_ok=True)
with lock_path.open('w') as lock, tempfile.TemporaryDirectory(prefix='nvalt-view-review-') as directory:
    fcntl.flock(lock, fcntl.LOCK_EX)
    require_clean_desktop()
    (args.output / 'frames').mkdir(parents=True, exist_ok=True)
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
    base = base.replace('#include "checks.inc"', helpers + '\n' + (source / 'capture.inc').read_text())
    prefix = (source / 'prefix.h').read_text()
    harness = root / 'Review.m'
    harness.write_text(prefix + '\n' + base)
    dylib = root / 'ViewReview.dylib'
    subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-dynamiclib',
        '-undefined', 'dynamic_lookup', '-fno-objc-arc', '-Wno-deprecated-declarations',
        *include_flags(repo), '-I', str(source),
        '-include', str(repo / 'Config/Notation_Prefix.pch'), '-framework', 'Cocoa',
        '-framework', 'Carbon', '-framework', 'WebKit', '-o', str(dylib), str(harness)], check=True)
    env = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root), DYLD_INSERT_LIBRARIES=str(dylib),
        TMPDIR=str(root / 'Temp') + '/', NV_USER_SCHEMES_ARTIFACTS=str(args.output))
    binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
    try:
        log_path = args.output / 'launch-services.log'
        log_path.write_text('')
        launch = ['open', '-W', '-n', '--stdout', str(log_path), '--stderr', str(log_path)]
        for key in ['NV_WINDOW_TEST_DIRECTORY', 'DYLD_INSERT_LIBRARIES', 'TMPDIR',
                    'NV_USER_SCHEMES_ARTIFACTS']:
            launch.extend(['--env', key + '=' + env[key]])
        result = run_desktop_process(launch + [str(app), '--args', '-ShowDockIcon', 'YES',
            '-StatusBarItem', 'NO', '-QuitWhenClosingMainWindow', 'NO',
            '-SUEnableAutomaticChecks', 'NO'], timeout=args.timeout, app_binary=binary)
        log = log_path.read_text()
        print(log, end='')
        if result or 'README_DEMO_CAPTURE_PASS' not in log:
            raise SystemExit(result or 1)
        require_clean_desktop()
    finally:
        subprocess.run(['defaults', 'delete', info['CFBundleIdentifier']],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
