#!/usr/bin/env python3
"""Independent fixed-codec and highlighter-bridge checks for round two."""
from pathlib import Path
import hashlib
import json
import platform
import subprocess

here = Path(__file__).resolve().parent
root = here.parents[3]
build = root / 'build/OrgSourceReview/round2/torvalds'
build.mkdir(parents=True, exist_ok=True)
vendor = root / 'ThirdParty/TreeSitter'
output = []
def run(cmd):
    completed = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if completed.returncode:
        raise RuntimeError(f'{cmd!r}\n{completed.stdout}')
    return completed.stdout.strip()
metadata = {'head': run(['git', '-C', str(root), 'rev-parse', 'HEAD']),
            'host': platform.platform(), 'xcode': run(['xcodebuild', '-version'])}
include = ['-I', str(vendor / 'runtime/include'), '-I', str(vendor / 'org/src')]
for arch, minimum, flags, label in [
    ('x86_64', '10.13', [], 'intel-signed'),
    ('x86_64', '10.13', ['-funsigned-char'], 'intel-unsigned'),
    ('arm64', '11.0', [], 'arm64'),
    ('arm64', '11.0', ['-fsanitize=address,undefined', '-fno-omit-frame-pointer'], 'arm64-sanitized')]:
    base = ['xcrun', 'clang', '-arch', arch, '-mmacosx-version-min=' + minimum, '-std=c11', '-O2', '-fblocks'] + flags
    codec = build / ('codec-' + label)
    run(base + include + [str(here / 'codec.c'), '-o', str(codec)])
    output.append(label + ': ' + run([str(codec)]))
    if label == 'intel-unsigned':
        continue
    objects = []
    for source in sorted((root / 'Sources/Editor/TreeSitter').glob('NVTreeSitter*.c')):
        obj = build / (label + '-' + source.stem + '.o')
        run(base + include + ['-c', str(source), '-o', str(obj)])
        objects.append(str(obj))
    highlighter = build / ('highlighter-' + label + '.o')
    run(base + ['-Werror=unguarded-availability-new', '-Dts_parser_parse_with_options=NVReviewParse',
                '-I', str(root / 'Sources/Editor'), '-c', str(root / 'Sources/Editor/NVSourceHighlighter.m'), '-o', str(highlighter)])
    bridge = build / ('bridge-' + label)
    run(base + include + ['-I', str(root / 'Sources/Editor'), '-framework', 'Cocoa', str(here / 'bridge.m'), str(highlighter)] + objects + ['-o', str(bridge)])
    output.append(label + ': ' + run([str(bridge), str(root / 'Resources/Syntax')]))
    output.append(run(['xcrun', 'vtool', '-show-build', str(bridge)]))

manifest = json.loads((vendor / 'manifest.json').read_text())
for path, expected in manifest['files'].items():
    data = (vendor / path).read_bytes()
    assert len(data) == expected['bytes'], path
    assert hashlib.sha256(data).hexdigest() == expected['sha256'], path
assert sum(p['bytes'] for p in manifest['files'].values()) == manifest['vendored_bytes']
output.append(f"PASS: {len(manifest['files'])} vendored file hashes and byte counts; total byte count matches")
component = next(c for c in manifest['components'] if c['vendored_directories'] == ['org'])
assert list(component['local_patches']) == ['org/src/scanner.c']
assert 'org/LOCAL_PATCHES.md' in manifest['files']
upstream = root / 'build/OrgInvestigation/tree-sitter-org-next'
compared = []
for relative in ['LICENSE', 'src/parser.c', 'src/scanner.c', 'src/tree_sitter/parser.h', 'src/tree_sitter/alloc.h', 'src/tree_sitter/array.h']:
    original = subprocess.check_output(['git', '-C', str(upstream), 'show', component['commit'] + ':' + relative])
    different = original != (vendor / 'org' / relative).read_bytes()
    assert different == (relative == 'src/scanner.c'), relative
    compared.append(relative)
output.append('PASS: the scanner is the only modified file among the six copied Org upstream files')
notice = (root / 'Resources/Syntax/ThirdPartyNotices.txt').read_text()
assert (vendor / 'org/LICENSE').read_text() in notice
assert 'Org scanner state serialization, decoding, and failure reporting are patched' in notice
output.append('PASS: distribution notices contain the complete Org MIT license and name the local modification')
metadata['codec_sha256'] = hashlib.sha256((here / 'codec.c').read_bytes()).hexdigest()
metadata['bridge_sha256'] = hashlib.sha256((here / 'bridge.m').read_bytes()).hexdigest()
(here / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
(here / 'output.txt').write_text('\n\n'.join(output) + '\n')
print('\n\n'.join(output))
