#!/usr/bin/env python3
"""Prove the native probe detects invalidating display permission on edits."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[4]
source = (root / 'Sources/Editor/NVSourceHighlighter.m').read_text()
old = 'if (captureRevision) ((NVSourceCaptureRevision *)captureRevision)->current = NO;'
assert source.count(old) == 1
mutant = root / 'build/SyntaxFlickerReview/round1/linus/mutant.m'
mutant.parent.mkdir(parents=True, exist_ok=True)
mutant.write_text(source.replace(old, 'if (captureRevision) ((NVSourceCaptureRevision *)captureRevision)->valid = NO;'))
result = subprocess.run([
    sys.executable, str(root / 'Tests/SyntaxFlickerReview/run-parser-probe.py'),
    '--probe', str(Path(__file__).with_name('probe.m')),
    '--implementation', str(mutant),
], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
print(result.stdout, end='')
assert result.returncode == 1, 'Mutant must fail.'
assert 'FAIL: Unicode prefix insertion: preceding revision remains displayable' in result.stdout
print('PASS: independent native mutation failed at the intended retained-display assertion.')
