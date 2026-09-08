#!/usr/bin/env python3
"""Check that the native probe rejects treating attribute edits as source edits."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[4]
source = (root / 'Sources/Editor/NVSourceHighlighter.m').read_text()
old = 'if (!([storage editedMask] & NSTextStorageEditedCharacters) || closed) return;'
assert source.count(old) == 1
mutant = root / 'build/SyntaxFlickerReview/round2/linus/mutant.m'
mutant.parent.mkdir(parents=True, exist_ok=True)
mutant.write_text(source.replace(old, 'if (closed) return;'))
result = subprocess.run([
    sys.executable, str(root / 'Tests/SyntaxFlickerReview/run-parser-probe.py'),
    '--probe', str(Path(__file__).with_name('probe.m')),
    '--implementation', str(mutant),
], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
print(result.stdout, end='')
assert result.returncode == 1, 'Mutant must fail.'
assert 'FAIL: attribute-only changes do not obsolete source analysis' in result.stdout
print('PASS: isolated mutation failed at the intended attribute-only edit assertion.')
