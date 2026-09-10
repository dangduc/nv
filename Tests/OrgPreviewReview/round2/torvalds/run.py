#!/usr/bin/env python3
"""Review the fixed native rebuild and heading adapter from an immutable snapshot."""
from pathlib import Path
from html.parser import HTMLParser
from unittest.mock import patch
from urllib.parse import unquote
import importlib.util
import io
import json
import hashlib
import os
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
REVISION = '415cf6920bd5c74bc3911829431f3dcff7c4acb2'
CARGO = Path('/Users/duc/dev/nv/build/OrgPreviewInvestigation/rustup/toolchains/1.98.1-aarch64-apple-darwin/bin/cargo')
BUILD = ROOT / 'build/OrgPreviewReview/round2/torvalds'
BUILD.mkdir(parents=True, exist_ok=True)
lines, checks = [], 0
metadata = {'revision': REVISION}
def check(value, label):
    global checks
    checks += 1
    if not value: raise AssertionError(label)
    lines.append('PASS: ' + label)
def run(command, **kwargs):
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
    if result.returncode:
        raise RuntimeError(str(command) + '\n' + result.stderr.decode(errors='replace'))
    return result.stdout
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def normalized(path):
    data = bytearray(path.read_bytes())
    magic, cpu = struct.unpack_from('<2I', data)
    check((magic, cpu) == (0xfeedfacf, 0x01000007), path.name + ' has a thin Intel Mach-O header')
    offset, uuids = 32, []
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        command, length = struct.unpack_from('<2I', data, offset)
        if command == 0x1b:
            uuids.append(offset + 8)
            data[offset + 8:offset + 24] = bytes(16)
        offset += length
    check(len(uuids) == 1, path.name + ' contains exactly one UUID to normalize')
    return bytes(data)

class Headings(HTMLParser):
    def __init__(self, data):
        super().__init__(convert_charrefs=True)
        self.ids, self.links, self.opened, self.closed = [], {}, [], []
        self.active = None
        self.feed(data.decode())
    def handle_starttag(self, tag, attributes):
        attributes = dict(attributes)
        if tag in ['h1', 'h2', 'h3', 'h4', 'h5', 'h6']:
            self.opened.append(tag); self.ids.append(attributes.get('id'))
        if tag == 'a': self.active = [attributes.get('href'), '']
    def handle_data(self, data):
        if self.active is not None: self.active[1] += data
    def handle_endtag(self, tag):
        if tag in ['h1', 'h2', 'h3', 'h4', 'h5', 'h6']: self.closed.append(tag)
        if tag == 'a' and self.active is not None:
            self.links[self.active[1]] = self.active[0]; self.active = None
    def targets(self, label, index):
        return self.links[label].startswith('#') and unquote(self.links[label][1:]) == self.ids[index]

metadata['macos'] = run(['sw_vers']).decode().strip()
metadata['xcode'] = run(['xcodebuild', '-version']).decode().strip()
metadata['sdk'] = run(['xcrun', '--sdk', 'macosx', '--show-sdk-version']).decode().strip()

with tempfile.TemporaryDirectory(prefix='fixed-snapshot-', dir=BUILD) as directory:
    stage = Path(directory)
    archive = run(['git', '-C', str(ROOT), 'archive', REVISION, 'ThirdParty/OrgPreview', 'Scripts/rebuild-org-preview.py', 'Resources/OrgPreviewNotices.txt'])
    with tarfile.open(fileobj=io.BytesIO(archive)) as tree: tree.extractall(stage)
    source = stage / 'ThirdParty/OrgPreview'
    script = stage / 'Scripts/rebuild-org-preview.py'
    manifest_path = source / 'manifest.json'
    original_manifest = manifest_path.read_bytes()
    manifest = json.loads(original_manifest)
    helper = source / 'nv-org-preview'
    check(helper.stat().st_size == 366408 and digest(helper) == 'dc5c563e75589ed615bc9faaad465f093ba180ac9c1b6baa3c4b2d874123fcba', 'reviewed helper is the frozen 366,408-byte artifact')
    env = {key: value for key, value in os.environ.items() if not key.startswith('DYLD_')}
    cache = stage / 'empty-cargo-cache'; cache.mkdir()
    env['CARGO_HOME'] = str(cache)
    env['CARGO_NET_OFFLINE'] = 'true'
    check(not any(key.startswith('DYLD_') for key in env), 'caller supplies no DYLD variables')
    rebuilt = stage / 'rebuilt-helper'
    rebuilt.write_bytes(b'previous review output\n')
    result = run(['python3', str(script), '--cargo', str(CARGO), '--output', str(rebuilt)], cwd=stage, env=env)
    (HERE / 'rebuild-output.txt').write_bytes(result)
    log = (stage / 'build/org-preview-rebuild.log').read_text()
    (HERE / 'rebuild-log.txt').write_text(log)
    check(not any('stripping' in line and 'failed:' in line for line in log.splitlines()), 'direct Cargo build finishes without failed-strip warnings')
    check(rebuilt.stat().st_size == manifest['binary_bytes'], 'fixed script produces the expected stripped artifact size')
    check(normalized(helper) == normalized(rebuilt), 'clean rebuilt artifact equals the bundled artifact except its UUID')
    check(manifest_path.read_bytes() == original_manifest, 'rebuild without update-manifest preserves the recorded manifest')
    check(not any((cache / p).exists() and any((cache / p).rglob('*')) for p in ['registry/src','registry/index','registry/cache','git/db','git/checkouts']), 'fresh offline build uses no cached or downloaded dependency content')
    check(run(['xcrun', 'nm', '-Uj', str(rebuilt)]).decode().splitlines() == ['__mh_execute_header'], 'native symbol inspection confirms stripping')
    metadata['rebuilt_sha256'] = digest(rebuilt)
    metadata['bundled_sha256'] = digest(helper)
    metadata['build_script_sha256'] = digest(script)
    metadata['adapter_sha256'] = digest(source / 'src/main.rs')
    metadata['compiler'] = run([str(CARGO.parent / 'rustc'), '--version']).decode().strip()

    # Compile an ordinary native program with extra defined symbols. It is used
    # only to exercise the production artifact inspector's rejection path.
    ordinary_c = stage / 'ordinary.c'
    ordinary_c.write_text('#include <stdio.h>\nint review_visible_symbol(void) { return 0; }\nint main(void) { puts("<h1 id=\\\"nv-org-heading-1\\\">Org</h1>"); return review_visible_symbol(); }\n')
    unstripped = stage / 'ordinary-unstripped'
    run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', str(ordinary_c), '-o', str(unstripped)])
    spec = importlib.util.spec_from_file_location('reviewed_rebuild', script)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    try:
        module.inspect(unstripped)
        rejected = False
    except SystemExit as error:
        rejected = 'still contains symbols' in str(error)
    check(rejected, 'real unstripped native executable fails the production inspector')

    output = stage / 'protected-output'
    marker = b'preserve this previous artifact\n'
    target = stage / 'build/OrgPreviewRebuild/x86_64-apple-darwin/release/nv-org-preview'
    original_run = subprocess.run
    original_copy = shutil.copy2
    rejection_results = []
    for case in ['strip-warning', 'native-symbols', 'cargo-error']:
        output.write_bytes(marker)
        manifest_path.write_bytes(original_manifest)
        if case == 'native-symbols': shutil.copy2(unstripped, target)
        else: shutil.copy2(rebuilt, target)
        copies = []
        def fake_run(command, *args, **kwargs):
            if command[0] == str(CARGO) and command[1] == 'build':
                message = 'warning: stripping debug info with `rust-objcopy` failed: review test\n' if case == 'strip-warning' else 'review compiler failure\n' if case == 'cargo-error' else ''
                kwargs['stdout'].write(message)
                return subprocess.CompletedProcess(command, 9 if case == 'cargo-error' else 0)
            return original_run(command, *args, **kwargs)
        def observe_copy(*args, **kwargs):
            copies.append(args)
            return original_copy(*args, **kwargs)
        args = ['rebuild-org-preview.py', '--cargo', str(CARGO), '--output', str(output), '--update-manifest']
        diagnostics = io.StringIO()
        with patch.object(sys, 'argv', args), patch.object(module.subprocess, 'run', side_effect=fake_run), patch.object(module.shutil, 'copy2', side_effect=observe_copy), patch.object(sys, 'stderr', diagnostics):
            try: module.main(); failure = None
            except SystemExit as error: failure = str(error)
        check(failure is not None, case + ' makes the rebuild fail')
        check(not copies, case + ' is rejected before any artifact copy')
        check(output.read_bytes() == marker, case + ' preserves the previous output bytes')
        check(manifest_path.read_bytes() == original_manifest, case + ' preserves the complete manifest')
        rejection_results.append({'case':case, 'failure':failure, 'diagnostics':diagnostics.getvalue()})
    metadata['rejection_cases'] = rejection_results

    # Exercise a real filesystem copy failure before the destination opens.
    # This does not claim atomic recovery from a partially completed copy.
    shutil.copy2(rebuilt, target)
    output.write_bytes(marker); output.chmod(0o444)
    failed_copy = subprocess.run(['python3', str(script), '--cargo', str(CARGO), '--output', str(output), '--update-manifest'], cwd=stage, env=env, capture_output=True)
    output.chmod(0o644)
    check(failed_copy.returncode != 0 and b'PermissionError' in failed_copy.stderr, 'read-only destination causes a real artifact-copy failure')
    check(output.read_bytes() == marker, 'copy failure before opening the destination preserves previous output')
    check(manifest_path.read_bytes() == original_manifest, 'artifact-copy failure cannot update the manifest')

    unicode_source = '[[*予定 café 👩‍💻][Forward Unicode]]\n[[#café&"id%][Explicit Unicode]]\n* First\nBody.\n** 予定 café 👩‍💻\n:PROPERTIES:\n:CUSTOM_ID: café&"id%\n:ID: alias日本\n:END:\n[[#alias日本][Alias Unicode]]\n'
    duplicates = '[[Repeated α][First duplicate]]\n* Repeated α\n:PROPERTIES:\n:CUSTOM_ID: sharedα\n:END:\n* Repeated α\n:PROPERTIES:\n:CUSTOM_ID: sharedα\n:END:\n* Reserved\n:PROPERTIES:\n:CUSTOM_ID: nv-org-heading-2\n:END:\n'
    deep = '[[*Deep café][Deep]]\n******* Deep café\nBody.\n'
    fixtures = [('unicode-lf', unicode_source), ('unicode-crlf', unicode_source.replace('\n','\r\n')), ('unicode-no-final-newline', unicode_source.rstrip('\n')), ('reserved-duplicate-ids', duplicates), ('deep-heading', deep)]
    transport = stage / 'transport'; transport.mkdir()
    hashes = []
    for name, text in fixtures:
        data = text.encode()
        expected = run([str(helper)], input=data, cwd=transport)
        parsed = Headings(expected)
        check(parsed.ids and len(set(parsed.ids)) == len(parsed.ids), name + ' gives each heading a unique anchor')
        check(parsed.opened == parsed.closed, name + ' pairs all native heading tags')
        if name.startswith('unicode'):
            check(parsed.ids[1] == 'café&"id%', name + ' preserves the escaped Unicode explicit ID')
            check(all(parsed.targets(label, 1) for label in ['Forward Unicode','Explicit Unicode','Alias Unicode']), name + ' resolves all Unicode heading aliases')
        elif name == 'reserved-duplicate-ids':
            check(parsed.ids == ['sharedα','nv-org-heading-2-2','nv-org-heading-2'], 'later explicit ID is reserved before duplicate fallback allocation')
            check(parsed.targets('First duplicate', 0), 'duplicate Unicode title selects the first heading')
        else:
            check(parsed.opened == ['h6'] and parsed.targets('Deep', 0), 'deep heading uses a linked and balanced h6 element')
        for width in [1,2,5,13]:
            child = subprocess.Popen([str(rebuilt)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=transport)
            for offset in range(0, len(data), width): child.stdin.write(data[offset:offset+width]); child.stdin.flush()
            child.stdin.close(); child.stdin=None
            stdout, stderr = child.communicate(timeout=10)
            check(child.returncode == 0 and not stderr and stdout == expected, name + ' stays deterministic with ' + str(width) + '-byte input writes')
        hashes.append({'name':name,'input_bytes':len(data),'output_sha256':hashlib.sha256(expected).hexdigest()})
    check(not list(transport.iterdir()), 'heading conversions leave the working directory unchanged')
    metadata['heading_fixtures'] = hashes
metadata['checks'] = checks
(HERE / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
(HERE / 'output.txt').write_text('\n'.join(lines) + f'\nPASS: {checks} round-two native checks\n')
print('\n'.join(lines))
print(f'PASS: {checks} round-two native checks')
