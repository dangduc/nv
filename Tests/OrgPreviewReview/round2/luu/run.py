#!/usr/bin/env python3
"""Measure heading-index cost and check every local link against source intent."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote
import hashlib
import json
import re
import statistics
import subprocess
import time

here = Path(__file__).resolve().parent
repo = here.parents[3]
out = repo / 'build/OrgPreviewReview/round2/luu'
out.mkdir(parents=True, exist_ok=True)
helper = repo / 'ThirdParty/OrgPreview/nv-org-preview'
bundle = repo / 'build/DerivedData/Build/Products/Development/nvALT.app'
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
frozen = 'dc5c563e75589ed615bc9faaad465f093ba180ac9c1b6baa3c4b2d874123fcba'
assert digest(helper) == frozen
assert digest(bundle / 'Contents/Resources/nv-org-preview') == frozen
old = out / 'org-before-heading-index'
old.write_bytes(subprocess.check_output(['git', 'show', '4467e7a7251ff3846c6d255db3bd64f465fda6b2:ThirdParty/OrgPreview/nv-org-preview'], cwd=repo))
old.chmod(0o755)

class Capture(HTMLParser):
    def __init__(self, text):
        super().__init__(convert_charrefs=True)
        self.headings, self.links = [], []
        self.current_link = None
        self.feed(text)
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'}:
            self.headings.append(attrs.get('id'))
        if tag == 'a':
            self.current_link = {'href': attrs.get('href'), 'text': ''}
            self.links.append(self.current_link)
    def handle_endtag(self, tag):
        if tag == 'a': self.current_link = None
    def handle_data(self, text):
        if self.current_link is not None: self.current_link['text'] += text

def fixture(kind, headings, links_per_heading):
    source, targets = [], {}
    for i in range(headings):
        title = f'Entry {i}'
        if kind == 'duplicate' and i >= 2: title = 'Repeated café'
        source.append(f'* TODO {title} :journal:\n')
        if kind == 'duplicate':
            if i == 1: source.append(':PROPERTIES:\n:CUSTOM_ID: nv-org-heading-1\n:END:\n')
            if i >= 2: source.append(':PROPERTIES:\n:CUSTOM_ID: café/日本語\n:END:\n')
        elif i % 3 == 0:
            source.append(f':PROPERTIES:\n:CUSTOM_ID: entry-{i}\n:END:\n')
        source.append('Notes retain *emphasis* and =literal markers=. Café 日本語 👩‍💻.\n- [ ] Read the report\n- [X] Record the decision\n\n')
        for j in range(links_per_heading):
            if kind == 'duplicate' and i >= 2:
                target, intended = ('#café/日本語' if j % 2 else '*Repeated café'), 2
            else:
                intended = (i * 7 + j * 13) % headings
                target = f'*Entry {intended}' if j % 2 == 0 else f'Entry {intended}'
                if kind == 'duplicate' and intended >= 2: target, intended = '*Repeated café', 2
            label = f'ref-{i}-{j}'
            source.append(f'[[{target}][{label}]] ')
            targets[label] = intended
        source.append('\n\n')
    source.append('END_OF_NOTE_SENTINEL\n')
    return ''.join(source).encode(), targets

oracle_checks = 0
def oracle(text, headings, targets, kind):
    global oracle_checks
    parsed = Capture(text)
    assert len(parsed.headings) == headings
    assert None not in parsed.headings and len(set(parsed.headings)) == headings
    assert len(parsed.links) == len(targets)
    oracle_checks += 3
    for link in parsed.links:
        assert link['text'] in targets
        assert link['href'].startswith('#')
        assert unquote(link['href'][1:]) == parsed.headings[targets[link['text']]], link
        oracle_checks += 3
    if kind == 'duplicate':
        assert parsed.headings[1] == 'nv-org-heading-1'
        assert parsed.headings[0] != parsed.headings[1]
        assert parsed.headings[2] == 'café/日本語'
        oracle_checks += 3
    assert 'END_OF_NOTE_SENTINEL' in text
    oracle_checks += 1

cases = [('journal', n, 8) for n in (64, 256, 1024)]
cases += [('links', 64, n) for n in (16, 64, 256)]
cases += [('duplicate', n, 8) for n in (32, 256, 1024)]
records, source_hashes = [], {}
oracles = {}
for kind, count, density in cases:
    name = f'{kind}-{count}-{density}'
    data, targets = fixture(kind, count, density)
    path = out / f'{name}.org'
    path.write_bytes(data)
    source_hashes[name] = digest(path)
    oracles[name] = (count, targets, kind)
    times = {'before': [], 'after': []}
    memory = {'before': [], 'after': []}
    output_lengths = {}
    for trial in range(3):
        # Alternate order so one binary does not always receive the warmer run.
        order = [('before', old), ('after', helper)] if trial % 2 == 0 else [('after', helper), ('before', old)]
        for phase, binary in order:
            start = time.perf_counter()
            result = subprocess.run(['/usr/bin/time', '-l', str(binary)], input=data, capture_output=True, timeout=15)
            elapsed = (time.perf_counter() - start) * 1000
            assert result.returncode == 0, result.stderr.decode()
            html = result.stdout.decode()
            if phase == 'after': oracle(html, count, targets, kind)
            else: assert len(Capture(html).headings) == count and 'END_OF_NOTE_SENTINEL' in html
            times[phase].append(elapsed)
            memory[phase].append(int(re.search(rb'(\d+)\s+maximum resident set size', result.stderr)[1]))
            output_lengths[phase] = len(result.stdout)
    record = {'name': name, 'headings': count, 'links': len(targets), 'input_bytes': len(data),
              'wall_ms': times, 'max_rss_bytes': memory, 'output_bytes': output_lengths,
              'median_ms': {p: statistics.median(v) for p, v in times.items()}}
    records.append(record)
    print(json.dumps(record), flush=True)
(here / 'helper-output.json').write_text(json.dumps(records, indent=2) + '\n')

sdk = Path(subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip())
binary = out / 'renderer-probe'
subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-O2', '-fno-objc-arc', '-fblocks',
    '-framework', 'Foundation', '-lxml2', '-I', str(sdk / 'usr/include/libxml2'), '-I', str(repo / 'Sources/Preview'),
    str(repo / 'Sources/Preview/NVNoteContentSnapshot.m'), str(repo / 'Sources/Preview/NVMarkupRenderer.m'),
    str(here / 'renderer.m'), '-o', str(binary)], check=True)
output = []
for name in ['journal-1024-8', 'links-64-256', 'duplicate-1024-8']:
    result = subprocess.run([str(binary), str(bundle), str(out / f'{name}.org'), str(out / f'{name}-renderer.html'), 'render'],
                            capture_output=True, text=True, timeout=20)
    output.append(result.stdout + result.stderr)
    result.check_returncode()
    oracle((out / f'{name}-renderer.html').read_text(), *oracles[name])
result = subprocess.run([str(binary), str(bundle), str(out / 'links-64-256.org'), str(out / 'newer-renderer.html'), 'replace'],
                        capture_output=True, text=True, timeout=20)
output.append(result.stdout + result.stderr)
result.check_returncode()
oracle((out / 'newer-renderer.html').read_text(), 1, {'newest-link': 0}, 'updated')
(here / 'renderer-output.txt').write_text('\n'.join(output))
assert source_hashes == {name: digest(out / f'{name}.org') for name in source_hashes}
metadata = {'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
    'before_helper_sha256': digest(old), 'reviewed_helper_sha256': digest(helper), 'reviewed_helper_bytes': helper.stat().st_size,
    'source_sha256': digest(repo / 'ThirdParty/OrgPreview/src/main.rs'), 'renderer_sha256': digest(repo / 'Sources/Preview/NVMarkupRenderer.m'),
    'fixture_sha256': source_hashes, 'oracle_checks': oracle_checks,
    'scope': 'Ordinary valid journals and merged duplicate IDs. No malformed converter input or live WebKit.'}
(here / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
print('\n'.join(output))
print(f'PASS: {oracle_checks} heading/link/content oracle assertions; source file hashes unchanged')
