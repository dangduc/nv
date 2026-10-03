#!/usr/bin/env python3
"""Rebuild the existing dependency versions for a native Apple Silicon CI job."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import runpy
import shutil
import subprocess
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parents[2]
PINS = ROOT / ".github/arm64-dependencies.json"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def unpack(archive, destination, expected):
    if digest(archive) != expected:
        raise ValueError("Dependency archive checksum mismatch: " + archive.name)
    with tarfile.open(archive) as source:
        source.extractall(destination, filter="data")
    roots = list(destination.iterdir())
    if len(roots) != 1 or not roots[0].is_dir():
        raise ValueError("Expected one source directory in " + archive.name)
    return roots[0]


def run(arguments, cwd=ROOT, env=None):
    print("+", " ".join(map(str, arguments)), flush=True)
    subprocess.run(list(map(str, arguments)), cwd=cwd, env=env, check=True)


def build(output, install=False):
    if platform.machine() != "arm64":
        raise RuntimeError("Run this dependency build natively on Apple Silicon.")
    output.mkdir(parents=True, exist_ok=True)
    pins = json.loads(PINS.read_text())
    environment = dict(os.environ, LC_ALL="C", MACOSX_DEPLOYMENT_TARGET="11.0")
    with tempfile.TemporaryDirectory(prefix="nv-arm64-deps-") as temporary:
        work = Path(temporary)
        sources = {}
        for name, pin in pins.items():
            archive = work / (name + ".tar.gz")
            run(["curl", "--fail", "--location", "--retry", "3", pin["url"], "--output", archive])
            destination = work / name
            destination.mkdir()
            sources[name] = unpack(archive, destination, pin["sha256"])

        # 1.0.2d predates Apple Silicon. Use its 64-bit portable C target, with
        # the Apple compiler selected explicitly and all assembly disabled.
        openssl = sources["openssl"]
        run(["perl", "Configure", "BSD-generic64", "no-shared", "no-asm",
             "-arch arm64", "-mmacosx-version-min=11.0", "-D_DARWIN_C_SOURCE"], openssl, environment)
        run(["make", "-j3", "CC=clang", "build_libs"], openssl, environment)
        shutil.copy2(openssl / "libcrypto.a", output / "libcrypto.a")
        shutil.copytree(openssl / "include/openssl", output / "include/openssl", dirs_exist_ok=True)

        markdown = sources["multimarkdown"]
        shutil.copytree(sources["greg"], markdown / "greg", dirs_exist_ok=True)
        flags = "-O2 -arch arm64 -mmacosx-version-min=11.0"
        run(["make", "-j3", "CC=clang", "CFLAGS=" + flags], markdown / "greg", environment)
        run(["make", "-j3", "multimarkdown", "CC=clang",
             "CFLAGS=" + flags + " -include GLibFacade.h"], markdown, environment)
        shutil.copy2(markdown / "multimarkdown", output / "multimarkdown")

    # Reuse the existing pinned, offline Org build and its validation. Keep the
    # tracked Intel helper and manifest unchanged unless --install is explicit.
    org = runpy.run_path(str(ROOT / "Scripts/rebuild-org-preview.py"))
    manifest = json.loads(org["MANIFEST"].read_text())
    if org["source_files"]() != manifest["source_sha256"]:
        raise ValueError("Org helper sources differ from their pinned manifest.")
    run(["python3", ROOT / "Scripts/rebuild-org-preview.py", "--arch", "arm64",
         "--output", output / "nv-org-preview"], env=environment)
    for name in ("libcrypto.a", "multimarkdown", "nv-org-preview"):
        actual = subprocess.check_output(["xcrun", "lipo", "-archs", output / name], text=True).strip()
        if actual != "arm64":
            raise ValueError(f"{name} has unexpected architecture: {actual}")
    run(["python3", ROOT / "Tests/CI/check-native-dependencies.py", output])
    record = {"arch": "arm64", "deployment_target": "11.0", "sources": pins,
              "org_rust_version": manifest["rust_version"],
              "binaries": {name: digest(output / name) for name in
                           ("libcrypto.a", "multimarkdown", "nv-org-preview")}}
    (output / "build.json").write_text(json.dumps(record, indent=2) + "\n")
    if install:
        for source, destination in (("libcrypto.a", "OpenSSL/lib/libcrypto.a"),
                                    ("multimarkdown", "MultiMarkdown/multimarkdown"),
                                    ("nv-org-preview", "OrgPreview/nv-org-preview")):
            shutil.copy2(output / source, ROOT / "ThirdParty" / destination)
        shutil.copytree(output / "include/openssl", ROOT / "ThirdParty/OpenSSL/include/openssl", dirs_exist_ok=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/arm64-dependencies")
    parser.add_argument("--install", action="store_true", help="stage into this disposable CI checkout")
    args = parser.parse_args()
    build(args.output.resolve(), args.install)
