#!/usr/bin/env python3
"""Check Finder and Dock icon selection using disposable application bundles."""

import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid


ROOT = Path(__file__).resolve().parents[2]


def check(catalog, output):
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="neo-icon-check-") as temporary:
        work = Path(temporary)
        probe = work / "check-icons"
        subprocess.run(["xcrun", "clang", "-fobjc-arc", "-framework", "AppKit",
                        str(Path(__file__).with_name("check-icons.m")), "-o", str(probe)], check=True)
        for name in ("Hybrid", "Classic", "Modern"):
            contents = work / (name + ".app") / "Contents"
            resources = contents / "Resources"
            resources.mkdir(parents=True)
            executable = contents / "MacOS/IconProbe"
            executable.parent.mkdir()
            shutil.copyfile(probe, executable)
            executable.chmod(0o755)
            info = {
                "CFBundleIdentifier": "org.neonotationalv.iconcheck." + uuid.uuid4().hex,
                "CFBundleName": name,
                "CFBundleExecutable": "IconProbe",
                "CFBundlePackageType": "APPL",
                "CFBundleVersion": "1",
                "LSUIElement": True,
                "CFBundleIconFile": "Notality.icns" if name == "Modern" else "NotalityClassic.icns",
            }
            for icon in ("Notality.icns", "NotalityClassic.icns"):
                shutil.copyfile(ROOT / "Resources/Images" / icon, resources / icon)
            if name != "Classic":
                info["CFBundleIconName"] = "NeoNotationalV"
                shutil.copyfile(catalog, resources / "Assets.car")
            (contents / "Info.plist").write_bytes(plistlib.dumps(info))
            subprocess.run([str(executable), "--application", str(work / (name + "-AppKit.png"))],
                           check=True, timeout=30)
        result = subprocess.run([str(probe), str(work)], timeout=30)
        for image in work.glob("*.png"):
            shutil.copyfile(image, output / image.name)
        result.check_returncode()
        version = subprocess.check_output(["sw_vers", "-productVersion"], text=True).strip()
        expected = "Modern" if int(version.split(".")[0]) >= 26 else "Classic"
        appkit = {name: (work / (name + "-AppKit.png.rgba")).read_bytes()
                  for name in ("Hybrid", "Classic", "Modern")}
        if appkit["Classic"] == appkit["Modern"]:
            raise RuntimeError("AppKit control icons are identical.")
        if appkit["Hybrid"] != appkit[expected]:
            raise RuntimeError(f"AppKit did not select {expected} on macOS {version}.")
        print(f"PASS: macOS {version} selects {expected} through NSApplication.applicationIconImage.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=ROOT / "Resources/Images/Assets.car")
    parser.add_argument("--output", type=Path, default=ROOT / "build/icon-selection")
    args = parser.parse_args()
    check(args.catalog, args.output)
