#!/usr/bin/env python3
"""Check that rebuild failures cannot replace the bundled Org artifact."""
from pathlib import Path
import os
import runpy
import shutil
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[3]
script = repo / 'Scripts/rebuild-org-preview.py'
with tempfile.TemporaryDirectory(prefix='nvalt-org-rebuild-') as temporary:
    work = Path(temporary)
    source = work / 'ThirdParty/OrgPreview'
    source.mkdir(parents=True)
    (work / 'Scripts').mkdir()
    shutil.copy2(script, work / 'Scripts/rebuild-org-preview.py')
    for name in ('manifest.json', 'Cargo.toml', 'Cargo.lock', 'rust-toolchain.toml'):
        shutil.copy2(repo / 'ThirdParty/OrgPreview' / name, source / name)
    toolchain = work / 'toolchain'
    toolchain.mkdir()
    cargo = toolchain / 'cargo'
    cargo.write_text('#!/usr/bin/env python3\nprint("warning: stripping debug info with `rust-objcopy` failed: signal: 6 (SIGABRT)")\n')
    rustc = toolchain / 'rustc'
    rustc.write_text('#!/usr/bin/env python3\nimport sys\nfrom pathlib import Path\nprint("rustc 1.98.1 (test fixture)" if sys.argv[1] == "--version" else str(Path(__file__).parent))\n')
    cargo.chmod(0o755)
    rustc.chmod(0o755)
    binary = source / 'nv-org-preview'
    binary.write_bytes(b'original artifact')
    manifest = (source / 'manifest.json').read_bytes()
    env = os.environ.copy()
    env['PATH'] = str(Path(sys.executable).parent) + os.pathsep + env.get('PATH', '')
    result = subprocess.run([sys.executable, str(work / 'Scripts/rebuild-org-preview.py'), '--cargo', str(cargo), '--update-manifest'], env=env, capture_output=True, text=True, timeout=15)
    assert result.returncode != 0 and 'could not strip' in result.stderr, result.stdout + result.stderr
    assert binary.read_bytes() == b'original artifact'
    assert (source / 'manifest.json').read_bytes() == manifest
    print('PASS successful Cargo exit with strip warning preserves artifact and manifest')

    unstripped = work / 'unstripped'
    subprocess.run(['xcrun', 'clang', '-x', 'c', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-', '-o', str(unstripped)], input=b'int main(void) { return 0; }\n', check=True)
    inspect = runpy.run_path(str(script))['inspect']
    try:
        inspect(unstripped)
    except SystemExit as error:
        assert 'still contains symbols' in str(error), error
    else:
        raise AssertionError('unstripped artifact was accepted')
    print('PASS artifact validation rejects cached unstripped output')
