#!/usr/bin/env python3
"""Exercise production syntax APIs and lazy session boundaries in a copied app."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import uuid

repo = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(repo / 'Tests'))
from compiler_support import include_flags

source = Path(os.environ.get('NV_ORG_TEST_APP', repo / 'build/DerivedData/Build/Products/Development/nvALT.app'))
if not source.exists():
    raise SystemExit('Build the Development app into build/DerivedData first.')
info = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
lock_path = repo / 'build/pr-review/gui.lock'
lock_path.parent.mkdir(parents=True, exist_ok=True)
with lock_path.open('w') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    with tempfile.TemporaryDirectory(prefix='nvalt-org-integration-') as root:
        root = Path(root)
        app = root / 'Org Integration.app'
        shutil.copytree(source, app, symlinks=True)
        info['CFBundleIdentifier'] = 'org.nvalt.window-tests.' + uuid.uuid4().hex
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        for name in ('Notes', 'Support', 'Temp'):
            (root / name).mkdir()
        dylib = root / 'OrgIntegration.dylib'
        harness = root / 'OrgIntegration.m'
        base = (repo / 'Tests/MultipleWindowsTests.m').read_text()
        prefix = base.split('- (void)nv_runTests {')[0] + '- (void)nv_runTests {'
        prefix = prefix.replace('[self setupViewsAfterAppAwakened];', '''Check([[[NSBundle mainBundle] bundleIdentifier] hasPrefix:@"org.nvalt.window-tests."], @"isolated copied-app preferences domain");
    Check([[[NSBundle mainBundle] bundlePath] hasPrefix:[TestDirectory stringByAppendingString:@"/"]], @"copied app and temporary library share the test root");
    [self setupViewsAfterAppAwakened];''')
        harness.write_text(Path(__file__).with_name('prefix.h').read_text() + '\n' + prefix + Path(__file__).with_name('probe.inc').read_text())
        subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-dynamiclib',
            '-undefined', 'dynamic_lookup', '-fno-objc-arc', '-Wno-deprecated-declarations',
            *include_flags(repo), '-include', str(repo / 'Config/Notation_Prefix.pch'),
            '-framework', 'Cocoa', '-framework', 'Carbon', '-framework', 'WebKit', '-o', str(dylib),
            str(harness)], check=True)
        environment = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root), DYLD_INSERT_LIBRARIES=str(dylib), TMPDIR=str(root / 'Temp') + '/')
        binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
        output = Path(__file__).with_name('output.txt')
        log = output.open('w')
        process = subprocess.Popen([str(binary), '-ShowDockIcon', 'YES', '-StatusBarItem', 'NO', '-QuitWhenClosingMainWindow', 'NO'], env=environment, stdout=log, stderr=subprocess.STDOUT)
        try:
            result = process.wait(timeout=90)
        except subprocess.TimeoutExpired:
            process.kill()
            raise SystemExit('Org integration timed out; kill sent to disposable process ' + str(process.pid))
        log.close()
        evidence = {
            'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
            'app': str(source),
            'app_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
            'architecture': 'x86_64 (Rosetta)',
            'macos': subprocess.check_output(['sw_vers'], text=True).strip(),
            'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
            'exit_status': result,
            'passes': output.read_text().count('PASS:'),
            'isolation': 'temporary copied app, UUID defaults domain, temporary notes and support directories',
            'source_sha256': {str(path.relative_to(repo)): hashlib.sha256(path.read_bytes()).hexdigest() for path in [repo / name for name in ('Sources/Model/NoteObject.m', 'Sources/Editor/NVNoteEditingSession.m', 'Sources/Browser/AppController_Preview.m', 'Sources/Application/NVApplicationController.m')]},
        }
        Path(__file__).with_name('evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
        print(output.read_text())
        if result:
            raise SystemExit(result)
