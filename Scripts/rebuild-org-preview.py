#!/usr/bin/env python3
"""Rebuild the bundled Org converter from pinned, offline Rust sources."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

REPO = Path(__file__).resolve().parents[1]
SOURCE = REPO / "ThirdParty/OrgPreview"
MANIFEST = SOURCE / "manifest.json"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_files():
    roots = [SOURCE / name for name in ("src", "orgize", "vendor", ".cargo", "licenses")]
    files = [p for root in roots for p in root.rglob("*") if p.is_file()]
    files += [SOURCE / name for name in ("Cargo.toml", "Cargo.lock", "rust-toolchain.toml")]
    return {str(p.relative_to(SOURCE)): digest(p) for p in sorted(files)}


def inspect(binary):
    arch = subprocess.check_output(["xcrun", "lipo", "-archs", str(binary)], text=True).strip()
    if arch != "x86_64":
        raise SystemExit("The Org helper must contain only the x86_64 architecture.")
    version = subprocess.check_output(["xcrun", "vtool", "-show-build", str(binary)], text=True)
    if "version 10.13" not in version and "minos 10.13" not in version:
        raise SystemExit("The Org helper must target macOS 10.13.")
    libraries = subprocess.check_output(["xcrun", "otool", "-L", str(binary)], text=True)
    linked = [line.strip().split(" (", 1)[0] for line in libraries.splitlines()[1:] if line.strip()]
    if linked != ["/usr/lib/libSystem.B.dylib"]:
        raise SystemExit("The Org helper contains an unexpected dynamic dependency.")
    symbols = subprocess.check_output(["xcrun", "nm", "-Uj", str(binary)], text=True).splitlines()
    if symbols != ["__mh_execute_header"]:
        raise SystemExit("The Org helper still contains symbols. Remove build/OrgPreviewRebuild and rebuild.")
    smoke = subprocess.run([str(binary)], input=b"* Org\n", capture_output=True, timeout=5)
    if smoke.returncode != 0 or b'<h1 id="nv-org-heading-1">Org</h1>' not in smoke.stdout:
        raise SystemExit("The Org helper cannot run or render a heading on this Mac.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-only", action="store_true", help="check the bundle and source hashes without Rust")
    parser.add_argument("--cargo", default=shutil.which("cargo"), help="path to Cargo")
    parser.add_argument("--output", type=Path, default=SOURCE / "nv-org-preview")
    parser.add_argument("--update-manifest", action="store_true", help="record the rebuilt binary and source hashes")
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    inputs = source_files()
    if args.verify_only:
        if inputs != manifest.get("source_sha256"):
            raise SystemExit("Org helper sources differ from the recorded build inputs. Rebuild the helper.")
        if digest(args.output) != manifest.get("binary_sha256"):
            raise SystemExit("The bundled Org helper differs from the recorded binary hash.")
        if digest(REPO / "Resources/OrgPreviewNotices.txt") != manifest.get("resource_notices_sha256"):
            raise SystemExit("The Org dependency notices differ from the recorded distribution notices.")
        inspect(args.output)
        print("Org helper: source hashes, binary hash, x86_64, macOS 10.13, and system library verified")
        return
    if not args.cargo:
        raise SystemExit("Rebuilding the helper requires Cargo and Rust 1.98.1. App builds use the bundled helper.")
    cargo = Path(args.cargo).absolute()
    env = os.environ.copy()
    env["PATH"] = str(cargo.parent) + os.pathsep + env.get("PATH", "")
    env["RUSTUP_TOOLCHAIN"] = manifest["rust_version"]
    env["MACOSX_DEPLOYMENT_TARGET"] = manifest["deployment_target"]
    env["CARGO_TARGET_DIR"] = str(REPO / "build/OrgPreviewRebuild")
    env["RUSTFLAGS"] = "--remap-path-prefix=" + str(REPO) + "=/nv-org-preview"
    version = subprocess.check_output(["rustc", "--version"], cwd=SOURCE, env=env, text=True).strip()
    if not version.startswith("rustc " + manifest["rust_version"] + " "):
        raise SystemExit("The helper requires the Rust version in its manifest.")
    # A direct Cargo path bypasses rustup's library path setup for rust-objcopy.
    sysroot = subprocess.check_output(["rustc", "--print", "sysroot"], cwd=SOURCE, env=env, text=True).strip()
    env["DYLD_LIBRARY_PATH"] = str(Path(sysroot) / "lib") + (os.pathsep + env["DYLD_LIBRARY_PATH"] if env.get("DYLD_LIBRARY_PATH") else "")
    log_path = REPO / "build/org-preview-rebuild.log"
    log_path.parent.mkdir(exist_ok=True)
    with log_path.open("w") as log:
        result = subprocess.run([str(cargo), "build", "--release", "--locked", "--offline", "--target", manifest["target"]],
                                cwd=SOURCE, env=env, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print(log_path.read_text(), file=sys.stderr)
        raise SystemExit(result.returncode)
    if any("stripping" in line and "failed:" in line for line in log_path.read_text().splitlines()):
        print(log_path.read_text(), file=sys.stderr)
        raise SystemExit("Rust could not strip the Org helper. The bundled artifact was not updated.")
    built = Path(env["CARGO_TARGET_DIR"]) / manifest["target"] / "release/nv-org-preview"
    inspect(built)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(built, args.output)
    args.output.chmod(0o755)
    if args.update_manifest:
        manifest["source_sha256"] = inputs
        manifest["binary_sha256"] = digest(args.output)
        manifest["binary_bytes"] = args.output.stat().st_size
        manifest["resource_notices_sha256"] = digest(REPO / "Resources/OrgPreviewNotices.txt")
        manifest["compiler"] = version
        manifest["sdk"] = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-version"], text=True).strip()
        MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Built {args.output} ({args.output.stat().st_size} bytes)")
    print(f"SHA-256: {digest(args.output)}")
    print(f"Compiler output: {log_path}")


if __name__ == "__main__":
    main()
