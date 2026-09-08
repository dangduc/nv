#!/usr/bin/env python3
"""Check native dependency replacements in a copied app with disposable notes and defaults."""
import os
import sys
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

repo = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags

import fcntl
lock_path = repo / 'build/pr-review/gui.lock'
lock_path.parent.mkdir(parents=True, exist_ok=True)
lock = lock_path.open('w')
fcntl.flock(lock, fcntl.LOCK_EX)
source = repo / 'build/DerivedData/Build/Products/Development/nvALT.app'
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
    harness.write_text(Path(__file__).with_name('support.h').read_text() + prefix + Path(__file__).with_name('probe-body.m').read_text())
    subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-dynamiclib',
        '-undefined', 'dynamic_lookup', '-fno-objc-arc', '-Wno-deprecated-declarations',
        *include_flags(repo), '-include', str(repo / 'Config/Notation_Prefix.pch'),
        '-framework', 'Cocoa', '-framework', 'Carbon', '-framework', 'WebKit', '-o', str(dylib),
        str(harness)], check=True)
    environment = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root), DYLD_INSERT_LIBRARIES=str(dylib), TMPDIR=str(root / 'Temp') + '/')
    binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
    arguments = [str(binary), '-ShowDockIcon', 'YES', '-StatusBarItem', 'NO',
        '-QuitWhenClosingMainWindow', 'NO']
    process = subprocess.Popen(arguments, env=environment)
    try:
        result = process.wait(timeout=60)
    except subprocess.TimeoutExpired:
        process.kill()
        # Rosetta may leave a crashed process uninterruptible. Do not wait forever
        # to reap it while holding the lock needed by other review agents.
        raise SystemExit('Probe timed out; kill sent to disposable process ' + str(process.pid))
    if result:
        raise SystemExit(result)
    raise SystemExit(0)
