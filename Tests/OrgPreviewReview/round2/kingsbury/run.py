#!/usr/bin/env python3
"""Exercise fixed Org heading links in native WK documents and retained state."""
from pathlib import Path
import fcntl
import hashlib
import json
import os
import platform
import plistlib
import shutil
import subprocess
import tempfile
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
inputs = [ROOT / name for name in [
    'Sources/Preview/NVNoteContentSnapshot.m',
    'Sources/Preview/NVMarkupRenderer.m',
    'Sources/Preview/PreviewController.m',
    'ThirdParty/OrgPreview/nv-org-preview',
    'ThirdParty/OrgPreview/src/main.rs',
    'ThirdParty/OrgPreview/manifest.json',
]]
before = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
common = Path(subprocess.check_output(['git', 'rev-parse', '--git-common-dir'], cwd=ROOT, text=True).strip())
if not common.is_absolute():
    common = (ROOT / common).resolve()
lock_path = common.parent / 'build/pr-review/gui.lock'
lock_path.parent.mkdir(parents=True, exist_ok=True)
with lock_path.open('w') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    with tempfile.TemporaryDirectory(prefix='nvalt-org-preview-r2-kingsbury-') as temporary:
        root = Path(temporary)
        app = root / 'Org State Tests.app'
        resources = app / 'Contents/Resources'
        resources.mkdir(parents=True)
        binary = app / 'Contents/MacOS/OrgStateTests'
        binary.parent.mkdir()
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'org.nvalt.org-preview-review.' + uuid.uuid4().hex,
            'CFBundleExecutable': binary.name,
            'CFBundlePackageType': 'APPL',
            'NSPrincipalClass': 'NSApplication',
            'NSHighResolutionCapable': True,
        }))
        shutil.copy2(inputs[3], resources / 'nv-org-preview')
        sdk = Path(subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip())
        subprocess.run([
            'xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13',
            '-fno-objc-arc', '-fblocks', '-Wno-deprecated-declarations',
            '-framework', 'Cocoa', '-framework', 'WebKit', '-lxml2',
            '-I', str(sdk / 'usr/include/libxml2'), '-I', str(ROOT / 'Sources/Preview'),
            *[str(path) for path in inputs[:3]], str(HERE / 'probe.m'), '-o', str(binary),
        ], check=True)
        result = subprocess.run([str(binary), str(root / 'export.html')],
            env=dict(os.environ), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
        (HERE / 'output.txt').write_text(result.stdout)
        print(result.stdout, end='')
        metadata = {
            'head_before_build': head,
            'input_sha256': before,
            'inputs_unchanged_during_run': before == {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs},
            'host': platform.platform(),
            'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
            'exit_code': result.returncode,
        }
        (HERE / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
        if not metadata['inputs_unchanged_during_run']:
            raise SystemExit('Production inputs changed during the run. Repeat after those edits finish.')
        raise SystemExit(result.returncode)
