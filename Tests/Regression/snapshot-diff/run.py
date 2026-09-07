#!/usr/bin/env python3
"""Validate exact production snapshot-diff hunks with native Foundation."""
import hashlib
from pathlib import Path
import subprocess
import tempfile

here = Path(__file__).resolve().parent
repo = here.parents[2]
source = (repo / 'Sources/Editor/NVNoteEditingSession.m').read_text()
start = source.index('static NSRange NVChangedRange(')
end = source.index('\n@implementation NVNoteEditingSession', start)
helper = source[start:end]
print('Production helper SHA256: ' + hashlib.sha256(helper.encode()).hexdigest(), flush=True)
with tempfile.TemporaryDirectory(prefix='nv-snapshot-diff-') as temporary:
    root = Path(temporary)
    (root / 'snapshot-helper.inc').write_text(helper)
    binary = root / 'probe'
    subprocess.run(['xcrun', 'clang', '-O2', '-fno-objc-arc', '-framework', 'Foundation',
        '-I', str(root), str(here / 'probe.m'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=45)
if (repo / 'Sources/Editor/NVNoteEditingSession.m').read_text()[start:end] != helper:
    raise SystemExit('Production helper changed while tests ran; rerun against the final source.')
