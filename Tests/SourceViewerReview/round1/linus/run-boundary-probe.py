#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[4]
sdk = Path(subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip())
with tempfile.TemporaryDirectory(prefix='nvalt-linus-review-') as temp:
    binary = Path(temp)/'renderer-boundary-probe'
    subprocess.run(['xcrun','clang','-arch','x86_64','-mmacosx-version-min=10.13','-fno-objc-arc','-fblocks','-lxml2','-I',str(sdk/'usr/include/libxml2'),'-framework','Foundation','-I',str(root/'Sources/Preview'),str(root/'Sources/Preview/NVNoteContentSnapshot.m'),str(root/'Sources/Preview/NVMarkupRenderer.m'),str(Path(__file__).with_name('renderer-boundary-probe.m')),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=50)
