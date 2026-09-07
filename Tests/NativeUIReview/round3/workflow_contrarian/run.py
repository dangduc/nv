#!/usr/bin/env python3
"""Run native keyboard traversal in an isolated Dark Aqua browser."""
import argparse
import fcntl
import hashlib
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
parser.add_argument('--probe', choices=['keyboard'], default='keyboard')
args = parser.parse_args()
source = args.app.resolve()
lock_path = repo / 'build/pr-review/gui.lock'
lock_path.parent.mkdir(parents=True, exist_ok=True)
with lock_path.open('w') as lock, tempfile.TemporaryDirectory(prefix='nvalt-r3-workflow-') as directory:
    fcntl.flock(lock, fcntl.LOCK_EX)
    root = Path(directory)
    app = root / 'Workflow Tests.app'
    shutil.copytree(source, app, symlinks=True)
    info_path = app / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info['CFBundleIdentifier'] = 'org.nvalt.r3-workflow.' + uuid.uuid4().hex
    info_path.write_bytes(plistlib.dumps(info))
    for name in ['Notes', 'Support', 'Temp']:
        (root / name).mkdir()
    executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
    print('SOURCE', subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(), flush=True)
    print('APP', source, 'EXECUTABLE_SHA256', hashlib.sha256(executable.read_bytes()).hexdigest(), flush=True)
    dylib = root / 'WorkflowTests.dylib'
    subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.14', '-dynamiclib',
        '-undefined', 'dynamic_lookup', '-fno-objc-arc', '-Wno-deprecated-declarations',
        '-I', str(repo), '-I', str(repo / 'RBSplitView'), '-I', str(repo / 'PTHotKeys'),
        '-I', str(repo / 'ODBEditor'), '-include', str(repo / 'Notation_Prefix.pch'),
        '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(dylib),
        str(Path(__file__).with_name('probes.m'))], check=True)
    output = root / 'probe.log'
    launch = ['open', '-W', '-n', '--stdout', str(output), '--stderr', str(output)]
    for key, value in dict(NV_WINDOW_TEST_DIRECTORY=str(root), DYLD_INSERT_LIBRARIES=str(dylib),
        TMPDIR=str(root / 'Temp') + '/', NV_WORKFLOW_PROBE=args.probe,
        NV_WORKFLOW_ARTIFACTS=str(Path(__file__).resolve().parent)).items():
        launch.extend(['--env', key + '=' + value])
    try:
        result = subprocess.run(launch + [str(app), '--args', '-ShowDockIcon', 'YES', '-StatusBarItem', 'NO',
            '-QuitWhenClosingMainWindow', 'NO', '-SUEnableAutomaticChecks', 'NO'], timeout=90)
        log = output.read_text() if output.exists() else ''
        print(log, end='')
    finally:
        subprocess.run(['defaults', 'delete', info['CFBundleIdentifier']],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    raise SystemExit(0 if result.returncode == 0 and 'WORKFLOW PROBES PASSED' in log else 1)
