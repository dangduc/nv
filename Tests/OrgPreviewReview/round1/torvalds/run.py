#!/usr/bin/env python3
"""Native packaging review from an immutable Git snapshot and empty Cargo cache."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse
import hashlib
import io
import json
import os
import platform
import shutil
import struct
import subprocess
import tarfile
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--revision', default='4467e7a7251ff3846c6d255db3bd64f465fda6b2')
parser.add_argument('--cargo', type=Path, default=Path('/Users/duc/dev/nv/build/OrgPreviewInvestigation/rustup/toolchains/1.98.1-aarch64-apple-darwin/bin/cargo'))
parser.add_argument('--toolchain-library-path', action='store_true', help='controlled experiment: supply the direct toolchain LLVM runtime directory')
parser.add_argument('--app', type=Path, default=ROOT / 'build/DerivedData/Build/Products/Development/nvALT.app')
args = parser.parse_args()
BUILD = ROOT / 'build/OrgPreviewReview/round1/torvalds'
BUILD.mkdir(parents=True, exist_ok=True)
checks = 0
lines = []
def check(ok, label):
    global checks
    checks += 1
    if not ok:
        raise AssertionError(label)
    lines.append('PASS: ' + label)
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def run(command, **kwargs):
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
    if result.returncode:
        raise RuntimeError(str(command) + '\n' + result.stderr.decode(errors='replace'))
    return result.stdout

def macho(path):
    """Decode the actual binary instead of grepping formatted tool output."""
    data = bytearray(path.read_bytes())
    magic, cpu, subtype, filetype, ncmds, sizecmds, flags, reserved = struct.unpack_from('<8I', data)
    check(magic == 0xfeedfacf and cpu == 0x01000007 and filetype == 2, path.name + ' is a thin Intel Mach-O executable')
    offset = 32
    minimum, libraries, uuid_offsets = None, [], []
    for _ in range(ncmds):
        command, size = struct.unpack_from('<2I', data, offset)
        if command == 0x24:
            minimum = struct.unpack_from('<I', data, offset + 8)[0]
        if command == 0x32:
            minimum = struct.unpack_from('<I', data, offset + 12)[0]
        if command == 0xc:
            nameoffset = struct.unpack_from('<I', data, offset + 8)[0]
            end = data.index(0, offset + nameoffset, offset + size)
            libraries.append(bytes(data[offset + nameoffset:end]).decode())
        if command == 0x1b:
            uuid_offsets.append(offset + 8)
            data[offset + 8:offset + 24] = bytes(16)
        offset += size
    check(offset == 32 + sizecmds, path.name + ' has consistent load-command bounds')
    check(minimum == (10 << 16 | 13 << 8), path.name + ' declares macOS 10.13 exactly')
    check(libraries == ['/usr/lib/libSystem.B.dylib'], path.name + ' links only libSystem')
    check(len(uuid_offsets) == 1, path.name + ' contains one Mach-O UUID')
    return bytes(data), uuid_offsets[0]

metadata = {'revision': run(['git', '-C', str(ROOT), 'rev-parse', args.revision]).decode().strip(),
            'host': platform.platform(), 'xcode': run(['xcodebuild', '-version']).decode().strip()}
with tempfile.TemporaryDirectory(prefix='clean-snapshot-', dir=BUILD) as temporary:
    stage = Path(temporary)
    archive = run(['git', '-C', str(ROOT), 'archive', metadata['revision'],
                   'ThirdParty/OrgPreview', 'Scripts/rebuild-org-preview.py',
                   'Resources/OrgPreviewNotices.txt', 'Notation.xcodeproj/project.pbxproj'])
    with tarfile.open(fileobj=io.BytesIO(archive)) as snapshot:
        snapshot.extractall(stage)
    source = stage / 'ThirdParty/OrgPreview'
    manifest = json.loads((source / 'manifest.json').read_text())
    check(digest(source / 'nv-org-preview') == manifest['binary_sha256'], 'snapshot binary hash matches the snapshot manifest')
    cache = stage / 'empty-cargo-cache'
    cache.mkdir()
    env = os.environ.copy()
    env['CARGO_HOME'] = str(cache)
    env['CARGO_NET_OFFLINE'] = 'true'
    env['PATH'] = str(args.cargo.parent) + os.pathsep + env.get('PATH', '')
    env['MACOSX_DEPLOYMENT_TARGET'] = '10.13'
    metadata['toolchain_library_path_override'] = args.toolchain_library_path
    if args.toolchain_library_path:
        env['DYLD_LIBRARY_PATH'] = str(args.cargo.parent.parent / 'lib')
    metadata['compiler'] = run([str(args.cargo.parent / 'rustc'), '--version'], env=env).decode().strip()
    check(metadata['compiler'] == manifest['compiler'], 'direct compiler is the recorded pinned toolchain')
    graph = json.loads(run([str(args.cargo), 'metadata', '--format-version', '1', '--locked', '--offline', '--filter-platform', 'x86_64-apple-darwin'], cwd=source, env=env))
    packages = {p['name']: p for p in graph['packages']}
    recorded = {p['name']: p for p in manifest['packages']}
    check(set(packages) == set(recorded) | {'nv-org-preview'}, 'resolved graph contains only the helper and eight recorded dependencies')
    for name, package in packages.items():
        check(Path(package['manifest_path']).is_relative_to(source), name + ' resolves inside the isolated staged sources')
        if name != 'nv-org-preview':
            check(package['version'] == recorded[name]['version'], name + ' resolved version matches its manifest entry')
    nodes = {next(p['name'] for p in graph['packages'] if p['id'] == n['id']): n for n in graph['resolve']['nodes']}
    check(nodes['orgize']['features'] == [], 'Orgize serialization and WASM defaults are disabled')
    check(nodes['indextree']['features'] == ['std'], 'indextree enables std without macro/procedural dependencies')
    build_scripts = sorted(p['name'] for p in graph['packages'] if any('custom-build' in t['kind'] for t in p['targets']))
    check(build_scripts == ['jetscii'], 'jetscii is the sole build script in the resolved graph')
    metadata['resolved_features'] = {name: n['features'] for name, n in nodes.items()}
    metadata['build_scripts'] = build_scripts
    rebuild = stage / 'rebuilt-helper'
    rebuild_command = ['python3', str(stage / 'Scripts/rebuild-org-preview.py'), '--cargo', str(args.cargo), '--output', str(rebuild)]
    if args.toolchain_library_path:
        # macOS removes inherited DYLD_* when launching its system Python. Set
        # the controlled variable inside that process, before the script runs.
        bootstrap = 'import os,runpy,sys; os.environ["DYLD_LIBRARY_PATH"] = ' + repr(str(args.cargo.parent.parent / 'lib')) + '; sys.argv = sys.argv[1:]; runpy.run_path(sys.argv[0], run_name="__main__")'
        rebuild_command = ['python3', '-c', bootstrap] + rebuild_command[1:]
    built_output = run(rebuild_command, cwd=stage, env=env)
    (HERE / 'rebuild-output.txt').write_bytes(built_output)
    shutil.copy2(stage / 'build/org-preview-rebuild.log', HERE / 'rebuild-log.txt')
    check(rebuild.is_file() and os.access(rebuild, os.X_OK), 'clean locked/offline rebuild produced an executable helper')
    metadata['cargo_cache_files'] = sorted(str(p.relative_to(cache)) for p in cache.rglob('*') if p.is_file())
    check(all(not (cache / suffix).exists() or not any((cache / suffix).rglob('*')) for suffix in ['registry/src', 'registry/cache', 'registry/index', 'git/db', 'git/checkouts']), 'empty Cargo cache gained no registry or Git dependency content')
    normalized_shipped, uuid = macho(source / 'nv-org-preview')
    normalized_rebuilt, rebuilt_uuid = macho(rebuild)
    shutil.copy2(source / 'nv-org-preview', BUILD / 'snapshot-helper')
    shutil.copy2(rebuild, BUILD / 'rebuilt-helper')
    metadata['only_uuid_differs'] = uuid == rebuilt_uuid and normalized_shipped == normalized_rebuilt
    metadata['differing_bytes_after_uuid_mask'] = sum(a != b for a, b in zip(normalized_shipped, normalized_rebuilt))
    lines.append('INFO: only_uuid_differs=' + str(metadata['only_uuid_differs']) + ', differing_bytes_after_uuid_mask=' + str(metadata['differing_bytes_after_uuid_mask']))
    metadata['snapshot_binary_sha256'] = digest(source / 'nv-org-preview')
    metadata['rebuilt_binary_sha256'] = digest(rebuild)
    metadata['binary_bytes'] = rebuild.stat().st_size
    metadata['uuid_offset'] = uuid
    if args.toolchain_library_path:
        check(metadata['only_uuid_differs'], 'with toolchain runtime supplied, clean rebuild differs only in the Mach-O UUID')
    # The application bundle is a fixed external artifact, not part of the mutable source snapshot.
    resources = args.app / 'Contents/Resources'
    app_helper = resources / 'nv-org-preview'
    packaged = stage / 'app-packaged-helper'
    shutil.copy2(app_helper, packaged)
    check(digest(packaged) == manifest['binary_sha256'], 'built app contains exactly the reviewed snapshot helper')
    check(os.access(app_helper, os.X_OK), 'app resource retains executable permission')
    for relative in ['OrgPreviewNotices.txt', 'Rust-1.98.1-COPYRIGHT-library.html']:
        expected = stage / 'Resources' / relative if relative.endswith('.txt') else source / 'licenses' / relative
        check((resources / relative).read_bytes() == expected.read_bytes(), 'built app carries exact ' + relative)
    notices = (stage / 'Resources/OrgPreviewNotices.txt').read_text()
    for package in recorded.values():
        for license_file in package['license_files']:
            check((source / license_file).read_text().strip() in notices, package['name'] + ' distribution notice contains ' + Path(license_file).name)
    # Normal transport fixtures include deliberate UTF-8 chunk boundaries, but no
    # invalid note payloads, extreme nesting, executable snippets, or stress sizes.
    fixtures = [
        ('empty', '', []),
        ('heading', '* Review\n', ['<h1>Review</h1>']),
        ('no-final-newline', '* Review', ['Review']),
        ('crlf', '* Review\r\nBody.\r\n', ['Review', 'Body.']),
        ('unicode', '* café 日本語 👩‍💻\nDecomposed e\u0301.\n', ['café 日本語 👩‍💻', 'e\u0301']),
        ('lists', '- one\n- two\n', ['<li>', 'one', 'two']),
        ('literal', '#+BEGIN_EXAMPLE\n<a> & value\n#+END_EXAMPLE\n', ['&lt;a&gt;', '&amp; value']),
        ('emphasis', 'Body *bold*, /italic/, and ~literal~.\n', ['<b>bold</b>', '<i>italic</i>', '<code>literal</code>']),
        ('relative-link', '[[file:photo.png][Photo]]\n', ['href="photo.png"', 'Photo']),
        ('table', '| Name | Value |\n|------+-------|\n| A | 1 |\n', ['<table>', 'Name', 'Value']),
        ('multilingual-body', 'Plain café 日本語 👩‍💻 and punctuation.\n' * 40, ['café 日本語 👩‍💻']),
    ]
    transport_dir = stage / 'transport'
    transport_dir.mkdir()
    subprocess_env = {'PATH': '/usr/bin:/bin', 'LANG': 'C', 'HOME': str(transport_dir)}
    def convert(binary, data, chunk):
        if chunk is None:
            return subprocess.run([str(binary)], input=data, cwd=transport_dir, env=subprocess_env, capture_output=True, timeout=10)
        process = subprocess.Popen([str(binary)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=transport_dir, env=subprocess_env)
        for offset in range(0, len(data), chunk):
            process.stdin.write(data[offset:offset + chunk]); process.stdin.flush()
        process.stdin.close(); process.stdin = None
        stdout, stderr = process.communicate(timeout=10)
        return subprocess.CompletedProcess([str(binary)], process.returncode, stdout, stderr)
    transport_results = []
    for name, text, expected in fixtures:
        payload = text.encode()
        reference = convert(source / 'nv-org-preview', payload, None)
        check(reference.returncode == 0 and not reference.stderr, name + ' exits successfully without diagnostics')
        html = reference.stdout.decode()
        check(all(fragment in html for fragment in expected), name + ' preserves expected ordinary rendered content')
        jobs = [(binary, chunk) for binary in [rebuild, packaged] for chunk in [1, 7, 4096]]
        with ThreadPoolExecutor(max_workers=4) as workers:
            results = list(workers.map(lambda pair: convert(pair[0], payload, pair[1]), jobs))
        check(all(p.returncode == 0 and not p.stderr and p.stdout == reference.stdout for p in results), name + ' matches across rebuilt/app helpers and three pipe chunk sizes')
        transport_results.append({'name': name, 'input_bytes': len(payload), 'output_sha256': hashlib.sha256(reference.stdout).hexdigest()})
    check(list(transport_dir.iterdir()) == [], 'all ordinary conversions leave the disposable working directory unchanged')
    metadata['transport_fixtures'] = transport_results
metadata['checks'] = checks
(HERE / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
(HERE / 'output.txt').write_text('\n'.join(lines) + f'\nPASS: {checks} native packaging and transport checks\n')
print('\n'.join(lines))
print(f'PASS: {checks} native packaging and transport checks')
