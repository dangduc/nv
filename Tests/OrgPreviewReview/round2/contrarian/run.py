#!/usr/bin/env python3
"""Check documented Org link semantics with independent ordinary-note fixtures."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote
import hashlib
import json
import platform
import subprocess

here = Path(__file__).resolve().parent
repo = here.parents[3]
out = repo / 'build/OrgPreviewReview/round2/contrarian'
out.mkdir(parents=True, exist_ok=True)
helper = repo / 'ThirdParty/OrgPreview/nv-org-preview'
bundle = repo / 'build/DerivedData/Build/Products/Development/nvALT.app'
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
production = [helper, repo / 'ThirdParty/OrgPreview/src/main.rs', repo / 'Sources/Preview/NVMarkupRenderer.m', repo / 'Sources/Preview/NVNoteContentSnapshot.m']
hashes = {str(path.relative_to(repo)): digest(path) for path in production}
head_before = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
assert digest(helper) == 'dc5c563e75589ed615bc9faaad465f093ba180ac9c1b6baa3c4b2d874123fcba'
assert digest(helper) == digest(bundle / 'Contents/Resources/nv-org-preview')

# Expectations identify target headings by document order, not by a copy of the
# converter's generated-ID algorithm. Visible text and unchanged path values
# are explicit fixture expectations from the documented preview subset.
fixtures = {
    'competing-aliases': {
        'source': '''[[#shared][First ID alias]]
[[#preferred][First custom]]
[[*Second][Second heading]]
[[#second-id][Second ID alias]]
[[*First *bold*][First raw title]]
[[First *bold*][First exact title]]
[[First bold][Visible title is not raw title]]

* TODO [#A] First *bold* :team:
:PROPERTIES:
:ID: shared
:CUSTOM_ID: preferred
:END:
First body.
* Second
:PROPERTIES:
:CUSTOM_ID: shared
:ID: second-id
:END:
Second body.
''',
        'headings': ['TODO [#A] First bold :team:', 'Second'],
        'ids': {0: 'preferred', 1: 'shared'},
        'targets': {'First ID alias': 0, 'First custom': 0, 'Second heading': 1, 'Second ID alias': 1, 'First raw title': 0, 'First exact title': 0},
        'paths': {'Visible title is not raw title': 'First bold'},
    },
    'unicode-percent': {
        'source': '''[[*Café é 👩🏽‍💻 東京][Unicode title]]
[[#東京#%20&"id][Literal percent ID]]
[[#review-α][Unicode alias]]

* Café é 👩🏽‍💻 東京
:PROPERTIES:
:CUSTOM_ID: 東京#%20&"id
:ID: review-α
:END:
Text *é 👩🏽‍💻* and =literal /markup/=.
''',
        'headings': ['Café é 👩🏽‍💻 東京'],
        'ids': {0: '東京#%20&"id'},
        'targets': {'Unicode title': 0, 'Literal percent ID': 0, 'Unicode alias': 0},
        'contains': ['é 👩🏽‍💻', 'literal /markup/'],
    },
    'path-title-ambiguity': {
        'source': '''[[Assets][Bare heading]]
[[file:Assets][Explicit file]]
[[./Assets][Relative file]]
[[../Assets][Parent file]]
[[/Assets][Absolute file]]
[[~/Assets][Home file]]
[[https://example.com/notes][Web URL]]
[[*https://example.com/notes][URL-named heading]]

* Assets
Directory notes.
* https://example.com/notes
An intentionally URL-named heading.
''',
        'headings': ['Assets', 'https://example.com/notes'],
        'targets': {'Bare heading': 0, 'URL-named heading': 1},
        'paths': {'Explicit file': 'Assets', 'Relative file': './Assets', 'Parent file': '../Assets', 'Absolute file': '/Assets', 'Home file': '~/Assets', 'Web URL': 'https://example.com/notes'},
    },
    'duplicate-titles': {
        'source': '''[[Repeated][Exact duplicate]]
[[*Repeated][Starred duplicate]]
[[#second][Explicit second]]
[[#first][Explicit first]]

* Repeated
:PROPERTIES:
:CUSTOM_ID: first
:END:
First body.
** Repeated
:PROPERTIES:
:CUSTOM_ID: second
:END:
Second body.
''',
        'headings': ['Repeated', 'Repeated'],
        'ids': {0: 'first', 1: 'second'},
        'targets': {'Exact duplicate': 0, 'Starred duplicate': 0, 'Explicit first': 0, 'Explicit second': 1},
    },
    'literal-protection': {
        'source': '''[[*Actual][Actual heading]]
[[*Example heading][Example is not a heading]]

* Actual
#+BEGIN_EXAMPLE
,* Example heading
:PROPERTIES:
:CUSTOM_ID: example-only
:END:
[[*Actual][Example link stays literal]]
#+END_EXAMPLE

[[https://example.com][*literal label* and /markers/]]
''',
        'headings': ['Actual'],
        'targets': {'Actual heading': 0},
        'paths': {'Example is not a heading': '*Example heading', '*literal label* and /markers/': 'https://example.com'},
        'contains': ['* Example heading', '[[*Actual][Example link stays literal]]', ':CUSTOM_ID: example-only'],
    },
    'reserved-name': {
        'source': '''[[*Automatic][First automatic]]
[[*Reserved][Later explicit ID]]
[[#nv-org-heading-1][Explicit generated-looking ID]]

* Automatic
Auto body.
* Reserved
:PROPERTIES:
:CUSTOM_ID: nv-org-heading-1
:END:
Reserved body.
''',
        'headings': ['Automatic', 'Reserved'],
        'ids': {1: 'nv-org-heading-1'},
        'targets': {'First automatic': 0, 'Later explicit ID': 1, 'Explicit generated-looking ID': 1},
    },
}
fixtures['crlf-aliases'] = dict(fixtures['competing-aliases'])
fixtures['crlf-aliases']['source'] = fixtures['competing-aliases']['source'].replace('\n', '\r\n')
for name, fixture in fixtures.items():
    (out / (name + '.org')).write_bytes(fixture['source'].encode('utf-8'))
input_hashes = {name: digest(out / (name + '.org')) for name in fixtures}

class Document(HTMLParser):
    def __init__(self, source):
        super().__init__(convert_charrefs=True)
        self.headings, self.links, self.text = [], [], ''
        self.heading = self.link = None
        self.feed(source)
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in ('h1', 'h2', 'h3', 'h4', 'h5', 'h6'):
            self.heading = {'id': attrs.get('id'), 'text': ''}
            self.headings.append(self.heading)
        if tag == 'a':
            self.link = {'href': attrs.get('href'), 'text': ''}
            self.links.append(self.link)
    def handle_endtag(self, tag):
        if tag in ('h1', 'h2', 'h3', 'h4', 'h5', 'h6'):
            self.heading = None
        if tag == 'a': self.link = None
    def handle_data(self, data):
        self.text += data
        if self.heading is not None: self.heading['text'] += data
        if self.link is not None: self.link['text'] += data

checks = []
def check(backend, name, label, passed, detail):
    checks.append({'backend': backend, 'fixture': name, 'check': label, 'passed': bool(passed), 'detail': detail})

def examine(backend, outputs):
    for name, fixture in fixtures.items():
        document = Document(outputs[name])
        headings = document.headings
        # libxml adds formatting whitespace and percent-encodes URL spaces.
        # Compare visible heading words and decoded paths, not serializer bytes.
        check(backend, name, 'visible headings preserve expected order and markup', [' '.join(h['text'].split()) for h in headings] == fixture['headings'], headings)
        ids = [h['id'] for h in headings]
        check(backend, name, 'every heading has a unique anchor', len(ids) == len(fixture['headings']) and all(ids) and len(set(ids)) == len(ids), ids)
        for index, expected in fixture.get('ids', {}).items():
            check(backend, name, 'explicit anchor ' + str(index), len(ids) > index and ids[index] == expected, ids)
        labels = [link['text'] for link in document.links]
        expected_labels = set(fixture.get('targets', {})) | set(fixture.get('paths', {}))
        check(backend, name, 'exact link labels remain visible', len(labels) == len(expected_labels) and set(labels) == expected_labels, document.links)
        links = {link['text']: link['href'] for link in document.links}
        for label, index in fixture.get('targets', {}).items():
            href = links.get(label, '') or ''
            check(backend, name, 'fragment target: ' + label, len(ids) > index and href.startswith('#') and unquote(href[1:]) == ids[index], {'href': href, 'target_heading_index': index, 'headings': headings})
        for label, target in fixture.get('paths', {}).items():
            check(backend, name, 'unchanged path: ' + label, unquote(links.get(label, '') or '') == target, links.get(label))
        for text in fixture.get('contains', []):
            check(backend, name, 'literal or Unicode text preserved: ' + text, text in document.text, document.text)

outputs = {}
for name in fixtures:
    result = subprocess.run([str(helper)], input=(out / (name + '.org')).read_bytes(), capture_output=True, timeout=5)
    assert result.returncode == 0, result.stderr.decode()
    outputs[name] = result.stdout.decode('utf-8')
    (out / (name + '-helper.html')).write_text(outputs[name])
examine('helper', outputs)

sdk = Path(subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip())
binary = out / 'renderer-probe'
subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-O2', '-fno-objc-arc', '-fblocks',
    '-framework', 'Foundation', '-lxml2', '-I', str(sdk / 'usr/include/libxml2'), '-I', str(repo / 'Sources/Preview'),
    str(repo / 'Sources/Preview/NVNoteContentSnapshot.m'), str(repo / 'Sources/Preview/NVMarkupRenderer.m'),
    str(here / 'renderer.m'), '-o', str(binary)], check=True)
result = subprocess.run([str(binary), str(bundle), str(out)], capture_output=True, text=True, timeout=45)
(here / 'renderer-output.txt').write_text(result.stdout + result.stderr)
assert result.returncode == 0, result.stdout + result.stderr
examine('renderer', {name: (out / (name + '-renderer.html')).read_text() for name in fixtures})
assert input_hashes == {name: digest(out / (name + '.org')) for name in fixtures}
assert hashes == {str(path.relative_to(repo)): digest(path) for path in production}, 'production input changed during review'
(here / 'results.json').write_text(json.dumps(checks, ensure_ascii=False, indent=2) + '\n')
(here / 'metadata.json').write_text(json.dumps({
    'head_before': head_before,
    'head_after': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
    'host': platform.platform(),
    'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
    'execution': 'x86_64 under Rosetta, macOS 10.13 build target',
    'production_sha256': hashes,
    'fixture_sha256': input_hashes,
    'scope': 'Ordinary documented Org preview semantics, production helper and renderer. No UI navigation or provider-state checks.'
}, indent=2) + '\n')
for item in checks:
    print(('PASS ' if item['passed'] else 'FAIL ') + ': '.join((item['backend'], item['fixture'], item['check'])))
failed = sum(not item['passed'] for item in checks)
print(f'{len(checks) - failed}/{len(checks)} expected-output checks passed; {failed} failed')
print(result.stdout, end='')
raise SystemExit(bool(failed))
