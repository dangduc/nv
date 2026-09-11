#!/usr/bin/env python3
"""Check real preview/editor teardown in a copied app with disposable notes and defaults."""
import argparse
import os
import sys
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--case', choices=['all', 'blank', 'rendered'], default='all')
parser.add_argument('--compile-only', action='store_true', help='compile both probe harnesses without launching an app')
args = parser.parse_args()
case = args.case
if case == 'all':
    for selected in ['blank', 'rendered']:
        subprocess.run([sys.executable, str(Path(__file__).resolve()), '--case', selected] + (['--compile-only'] if args.compile_only else []), check=True)
    raise SystemExit(0)

repo = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags

import fcntl
lock_path = repo / 'build/pr-review/gui.lock'
lock_path.parent.mkdir(parents=True, exist_ok=True)
lock = lock_path.open('w')
fcntl.flock(lock, fcntl.LOCK_EX)
source = repo / 'build/DerivedData/Build/Products/Development/nvALT Development.app'
if not source.exists():
    raise SystemExit('Build the Development app into build/DerivedData first.')
with tempfile.TemporaryDirectory(prefix='nvalt-window-tests-') as root:
    root = Path(root)
    app = root / 'Window Tests.app'
    shutil.copytree(source, app, symlinks=True)
    info_path = app / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    original_bundle_id = info['CFBundleIdentifier']
    info['CFBundleIdentifier'] = 'org.nvalt.window-tests.' + uuid.uuid4().hex
    assert info['CFBundleIdentifier'] != original_bundle_id
    assert app.resolve().is_relative_to(root.resolve())
    info_path.write_bytes(plistlib.dumps(info))
    (root / 'Notes').mkdir()
    (root / 'Support').mkdir()
    (root / 'Temp').mkdir()
    dylib = root / 'WindowTests.dylib'
    harness = root / 'ReviewProbe.m'
    base = (repo / 'Tests/MultipleWindowsTests.m').read_text()
    prefix = base.split('- (void)nv_runTests {')[0] + '- (void)nv_runTests {'
    prefix = prefix.replace('[self setupViewsAfterAppAwakened];', '''Check([[[NSBundle mainBundle] bundleIdentifier] hasPrefix:@"org.nvalt.window-tests."], @"isolated copied-app preferences domain");
    Check([[[NSBundle mainBundle] bundlePath] hasPrefix:[TestDirectory stringByAppendingString:@"/"]], @"copied app and temporary library share the test root");
    [self setupViewsAfterAppAwakened];''')
    harness.write_text('#import <WebKit/WebKit.h>\n#import "PreviewController.h"\n' + prefix + Path(__file__).with_name('probe-body.m' if case == 'blank' else 'rendered-body.m').read_text().replace('// NV_LIFETIME_INSTRUMENTATION', Path(__file__).with_name('instrumentation.inc').read_text()))
    subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-dynamiclib',
        '-undefined', 'dynamic_lookup', '-fno-objc-arc', '-Wno-deprecated-declarations',
        *include_flags(repo), '-include', str(repo / 'Config/Notation_Prefix.pch'),
        '-framework', 'Cocoa', '-framework', 'Carbon', '-framework', 'WebKit', '-o', str(dylib),
        str(harness)], check=True)
    if args.compile_only:
        print(f'PASS: {case} inline viewer lifetime harness compiles')
        raise SystemExit(0)
    environment = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root), DYLD_INSERT_LIBRARIES=str(dylib), TMPDIR=str(root / 'Temp') + '/')
    binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
    arguments = [str(binary), '-ShowDockIcon', 'YES', '-StatusBarItem', 'NO',
        '-QuitWhenClosingMainWindow', 'NO', '-SUEnableAutomaticChecks', 'NO']
    process = subprocess.Popen(arguments, env=environment)
    try:
        result = process.wait(timeout=90)
    except subprocess.TimeoutExpired:
        process.kill()
        # Rosetta may leave a crashed process uninterruptible. Do not wait forever
        # to reap it while holding the lock needed by other review agents.
        raise SystemExit('Probe timed out; kill sent to disposable process ' + str(process.pid))
    if result:
        raise SystemExit(result)
    raise SystemExit(0)
