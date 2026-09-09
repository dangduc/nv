#!/usr/bin/env python3
"""Build and open the isolated AppKit fuzzy-search prototype."""
import argparse
import json
import hashlib
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
UPSTREAM = ROOT / "ThirdParty/fzf-native"
PIN = "4b9236e8cd1e9f9f3aaf5f2ebf83f1fc5995d38d"
OUT = ROOT / "build/FuzzySearchPrototype"
APP = OUT / "NV Search Prototype.app"


def run(args):
    subprocess.run([str(arg) for arg in args], check=True, cwd=ROOT)


def build():
    manifest = json.loads((UPSTREAM / "upstream.json").read_text())
    revision = manifest["revision"]
    if revision != PIN:
        sys.exit(f"Expected fzf-native {PIN}; found {revision}.")
    for name, digest in manifest["files"].items():
        if hashlib.sha256((UPSTREAM / name).read_bytes()).hexdigest() != digest:
            sys.exit(f"Vendored source differs from its recorded digest: {name}")
    target = "arm64" if platform.machine() == "arm64" else "x86_64"
    OUT.mkdir(parents=True, exist_ok=True)
    resources = APP / "Contents/Resources"
    binary = APP / "Contents/MacOS/NV Search Prototype"
    resources.mkdir(parents=True, exist_ok=True)
    binary.parent.mkdir(parents=True, exist_ok=True)
    compile_flags = ["xcrun", "clang", "-arch", target, "-mmacosx-version-min=12.0", "-std=c11", "-O2",
                     "-DUTF8PROC_STATIC", "-I", UPSTREAM, "-I", HERE / "Core", "-c"]
    objects = []
    for name, source in [("bridge", HERE / "Core/NVFZF.c"), ("fzf", UPSTREAM / "fzf.c"),
                         ("utf8proc", UPSTREAM / "utf8proc-2.10.0/utf8proc.c")]:
        obj = OUT / f"{name}.o"
        run(compile_flags + [source, "-o", obj])
        objects.append(obj)
    module_cache = OUT / "ModuleCache"
    module_cache.mkdir(exist_ok=True)
    run(["xcrun", "swiftc", "-swift-version", "5", "-O", "-target", f"{target}-apple-macosx12.0",
         "-module-cache-path", module_cache, "-import-objc-header", HERE / "Core/NVFZF.h",
         HERE / "main.swift", *objects, "-framework", "AppKit", "-o", binary])
    plist = {
        "CFBundleName": "NV Search Prototype", "CFBundleDisplayName": "NV Search Prototype",
        "CFBundleIdentifier": "org.nvalt.fuzzy-search-prototype", "CFBundleExecutable": binary.name,
        "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "0.1",
        "LSMinimumSystemVersion": "12.0", "NSHighResolutionCapable": True,
        "NSPrincipalClass": "NSApplication", "NSHumanReadableCopyright": "Experimental nvALT search prototype",
    }
    (APP / "Contents/Info.plist").write_bytes(plistlib.dumps(plist))
    shutil.copy2(HERE / "Fixtures/sample-notes.json", resources / "sample-notes.json")
    licenses = resources / "Licenses"
    licenses.mkdir(exist_ok=True)
    for name, source in [("GPL-3.0.txt", UPSTREAM / "LICENSE"),
                         ("fzf-MIT.txt", UPSTREAM / "LICENSE-MIT"),
                         ("utf8proc-Unicode.md", UPSTREAM / "utf8proc-2.10.0/LICENSE.md")]:
        shutil.copy2(source, licenses / name)
    (resources / "upstream.json").write_text(json.dumps({
        "repository": "https://github.com/dangduc/fzf-native", "branch": "main", "revision": revision,
        "architecture": target, "prototype": "native fzf query syntax, whole-note candidates",
    }, indent=2) + "\n")
    run(["codesign", "--force", "--sign", "-", APP])
    print(f"Built {APP}", flush=True)
    return binary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-only", action="store_true", help="Build without opening a window")
    parser.add_argument("--check", action="store_true", help="Build and run native/Swift checks without opening a window")
    parser.add_argument("--ui-smoke", action="store_true", help="Build, run the disposable UI smoke check, then quit")
    args = parser.parse_args()
    binary = build()
    if args.check:
        run([sys.executable, HERE / "Core/Tests/run.py"])
        run([binary, "--self-test"])
    elif args.ui_smoke:
        subprocess.run([str(binary), "--ui-smoke"], check=True, timeout=25, cwd=ROOT)
    elif not args.build_only:
        run(["open", "-n", APP])


if __name__ == "__main__":
    main()
