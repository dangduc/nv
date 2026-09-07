#!/usr/bin/env python3
"""Require current production snapshots to preserve an interior span; reject old head."""
from pathlib import Path
import subprocess
import tempfile

here = Path(__file__).resolve().parent
repo = here.parents[2]
old_head = '3502c7c49660cb4750a9de7f02fedd7e6fd314e8'
with tempfile.TemporaryDirectory(prefix='nv-snapshot-control-') as temporary:
    temporary = Path(temporary)
    old_source = temporary / 'OldEditingSession.m'
    old_source.write_text(subprocess.check_output(
        ['git', 'show', old_head + ':NVNoteEditingSession.m'], cwd=repo, text=True))
    for name, source, expected in [('current-production', repo / 'NVNoteEditingSession.m', 0), ('old-head-negative-control', old_source, 1)]:
        binary = temporary / name
        subprocess.run(['xcrun', 'clang', '-O2', '-fno-objc-arc', '-Wno-deprecated-declarations',
            '-I', str(repo), '-I', str(repo / 'RBSplitView'), '-I', str(repo / 'PTHotKeys'),
            '-I', str(repo / 'ODBEditor'), '-include', str(repo / 'Notation_Prefix.pch'),
            '-framework', 'Cocoa', '-framework', 'Carbon', str(here / 'snapshot-control.m'),
            str(source), '-o', str(binary)], check=True)
        result = subprocess.run([str(binary)], text=True, capture_output=True, timeout=20)
        print(name + ':\n' + result.stdout, end='')
        assert result.returncode == expected, name + ': ' + result.stderr
        print('PASS: ' + name)
