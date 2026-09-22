#!/usr/bin/env python3
"""Check the committed icon catalog and optional built app resources."""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib


ROOT = Path(__file__).resolve().parents[2]
RESOURCES = ROOT / "Resources/Images"


def check(app=None):
    manifest = json.loads((RESOURCES / "Assets.car.json").read_text())
    hashes = {"Resources/Images/Assets.car": manifest["sha256"], **manifest["sources"]}
    for name, expected in hashes.items():
        path = (ROOT / name).resolve()
        if ROOT not in path.parents or not path.is_file():
            raise ValueError(f"Invalid icon source path: {name}")
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError(f"Icon resource changed; regenerate the catalog: {name}")
    if manifest["compiler"] != "Xcode 26.0.1\nBuild version 17A400":
        raise ValueError("The catalog must use the checked Xcode 26.0.1 compiler.")
    if manifest["icon_name"] != "NeoNotationalV":
        raise ValueError("Unexpected catalog icon name.")
    if app:
        contents = app / "Contents"
        info = plistlib.loads((contents / "Info.plist").read_bytes())
        for key, expected in {"CFBundleIconName": "NeoNotationalV",
                              "CFBundleIconFile": "NotalityClassic.icns"}.items():
            if info.get(key) != expected:
                raise ValueError(f"Unexpected {key}: {info.get(key)!r}")
        for name in ("Assets.car", "NotalityClassic.icns", "Notality.icns"):
            if (contents / "Resources" / name).read_bytes() != (RESOURCES / name).read_bytes():
                raise ValueError(f"App icon resource differs from the checked source: {name}")
    print("PASS: icon catalog hashes" + (" and app resources." if app else "."))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path)
    check(parser.parse_args().app)
