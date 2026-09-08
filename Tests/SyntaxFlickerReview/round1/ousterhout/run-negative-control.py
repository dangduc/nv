#!/usr/bin/env python3
"""Prove the probe detects conflating display validity with semantic currency."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[4]
original = root / 'Sources/Editor/NVSourceHighlighter.m'
target = root / 'build/SyntaxFlickerReview/round1/ousterhout/collapsed-contract.m'
source = original.read_text()
old = 'return revision && revision->valid && revision->sourceStorage == [layout textStorage];'
assert source.count(old) == 1
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(source.replace(old, 'return revision && revision->valid && revision->current && revision->sourceStorage == [layout textStorage];'))
result = subprocess.run(['python3', str(root / 'Tests/SyntaxFlickerReview/run-parser-probe.py'),
                         '--probe', str(Path(__file__).with_name('probe.m')),
                         '--implementation', str(target)], capture_output=True, text=True)
print(result.stdout, end='')
print(result.stderr, end='')
assert result.returncode != 0, 'Mutation was not detected'
assert 'pending source keeps display permission' in result.stderr, 'Failed for an unrelated reason'
print('PASS negative control: collapsing display/current failed the intended pending-display assertion')
