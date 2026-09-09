#!/usr/bin/env python3
"""Native independent measurements of production search presentation methods."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[5]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build/FuzzySearchReview/round-1/luu'
OUT.mkdir(parents=True, exist_ok=True)

def extract(path, prefixes, destination):
    source = (ROOT / path).read_text()
    selected = []
    for prefix in prefixes:
        start = source.index(prefix)
        selected.append(source[start:source.index('\n}', start) + 2])
    (OUT / destination).write_text('\n'.join(selected))

sources = ['Sources/Search/NVSearchQuery.m', 'Sources/Browser/AppController_Search.m', 'Sources/Editor/LinkingEditor.m']
extract(sources[1], ['- (void)refreshSearchHighlights'], 'refresh.inc')
extract(sources[2], ['- (void)removeHighlightedTerms', '- (void)setSearchHighlightRanges:'], 'editor.inc')
metadata = {
    'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
    'source_sha256': {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in sources},
    'host': subprocess.check_output(['sw_vers'], text=True).strip(),
    'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
    'architecture': 'arm64 (explicit compiler target)',
    'compiler': subprocess.check_output(['xcrun', 'clang', '--version'], text=True).strip(),
}
(HERE / 'source-record.json').write_text(json.dumps(metadata, indent=2) + '\n')
cmd = ['xcrun', 'clang', '-arch', 'arm64', '-O2', '-g', '-fblocks', '-fno-objc-arc', '-Wall', '-Wextra', '-Wno-unused-parameter', '-I' + str(OUT), '-I' + str(ROOT/'Sources/Search'), str(HERE/'highlight-probe.m'), str(ROOT/sources[0]), '-framework', 'Cocoa', '-o', str(OUT/'highlights')]
subprocess.run(cmd, check=True)
result = subprocess.run([str(OUT/'highlights'), *sys.argv[1:]], check=True, text=True, capture_output=True, timeout=90)
print(result.stdout, end='')
if result.stderr:
    print(result.stderr, file=sys.stderr)
(HERE / 'highlights.csv').write_text(result.stdout)
