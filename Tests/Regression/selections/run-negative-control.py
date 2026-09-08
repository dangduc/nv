#!/usr/bin/env python3
"""Require production snapshots to preserve an interior span; reject coarse replacement."""
from pathlib import Path
import sys
import subprocess
import tempfile

here = Path(__file__).resolve().parent
repo = here.parents[2]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags

production = repo / 'Sources/Editor/NVNoteEditingSession.m'
production_source = production.read_text()
start = production_source.index('    NSArray *edits = NVSnapshotEdits(', production_source.index('- (void)applyContents:'))
end = production_source.index('    // Source snapshots retain characters.', start)
coarse_source = production_source[:start] + '''    if (changed.length || replacement.length) {
        [textStorage replaceCharactersInRange:changed withAttributedString:[snapshot attributedSubstringFromRange:replacement]];
    }
''' + production_source[end:]
with tempfile.TemporaryDirectory(prefix='nv-snapshot-control-') as temporary:
    temporary = Path(temporary)
    coarse = temporary / 'CoarseEditingSession.m'
    coarse.write_text(coarse_source)
    for name, source, expected in [('current-production', production, 0), ('coarse-replacement-negative-control', coarse, 1)]:
        binary = temporary / name
        subprocess.run(['xcrun', 'clang', '-O2', '-fno-objc-arc', '-Wno-deprecated-declarations',
            *include_flags(repo), '-include', str(repo / 'Config/Notation_Prefix.pch'),
            '-framework', 'Cocoa', '-framework', 'Carbon', str(here / 'snapshot-control.m'),
            str(source), '-o', str(binary)], check=True)
        result = subprocess.run([str(binary)], text=True, capture_output=True, timeout=20)
        print(name + ':\n' + result.stdout, end='')
        assert result.returncode == expected, name + ': ' + result.stderr
        assert 'body_correct=1' in result.stdout and 'source_only=1 ignored_style_change=1' in result.stdout, name + ': source contract failed'
        if expected:
            assert 'edits=1 preserves_interior=0' in result.stdout, name + ': control failed for an unexpected reason'
        print('PASS: ' + name)
if production.read_text() != production_source:
    raise SystemExit('Production source changed while tests ran; rerun against the final source.')
