#!/usr/bin/env python3
"""Compile a Tahoe icon without replacing the separate classic fallback."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ARTWORK = Path(__file__).resolve().parent
ROOT = ARTWORK.parents[2]
ICON = ARTWORK / "NeoNotationalV.icon"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(destination, developer):
    environment = dict(os.environ, DEVELOPER_DIR=str(developer))
    version = subprocess.check_output(["xcodebuild", "-version"], env=environment, text=True).strip()
    # Later compilers ignore this flag and silently replace the legacy artwork.
    if version.splitlines()[0] != "Xcode 26.0.1":
        raise RuntimeError("Use Xcode 26.0.1 to preserve the separate classic icon.")
    with tempfile.TemporaryDirectory(prefix="neo-modern-icon-") as directory:
        output = Path(directory)
        subprocess.run([
            "xcrun", "actool", str(ICON), "--compile", str(output),
            "--app-icon", ICON.name, "--enable-on-demand-resources", "NO",
            "--development-region", "en", "--target-device", "mac",
            "--platform", "macosx", "--enable-icon-stack-fallback-generation=disabled",
            "--include-all-app-icons", "--minimum-deployment-target", "10.13",
            "--output-partial-info-plist", str(output / "Info.plist"),
        ], check=True, env=environment)
        catalog = output / "Assets.car"
        if not catalog.is_file() or catalog.stat().st_size == 0:
            raise RuntimeError("actool did not produce Assets.car.")
        records = json.loads(subprocess.check_output(
            ["xcrun", "assetutil", "--info", str(catalog)], env=environment))
        (output / "asset-info.json").write_text(json.dumps(records, indent=2) + "\n")
        destination.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(catalog, destination / "Assets.car")
        shutil.copyfile(output / "asset-info.json", destination / "asset-info.json")
        manifest = {
            "compiler": version,
            "icon_name": ICON.stem,
            "sha256": digest(catalog),
            "sources": {str(path.relative_to(ROOT)): digest(path)
                        for path in sorted(ICON.rglob("*")) if path.is_file()},
        }
        (destination / "Assets.car.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Compiled {destination / 'Assets.car'}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--developer-dir", type=Path,
                        default=Path("/Applications/Xcode_26.0.1.app/Contents/Developer"))
    parser.add_argument("--output", type=Path, default=ROOT / "build/modern-icon")
    arguments = parser.parse_args()
    build(arguments.output, arguments.developer_dir)
