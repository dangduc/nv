#!/usr/bin/env python3
"""Round-one configuration and legacy directory boundary evidence; no GUI or user data."""
from pathlib import Path
import importlib.util
import plistlib
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
spec = importlib.util.spec_from_file_location("identity", REPO / ".github/scripts/check-app-identity.py")
identity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(identity)

source = (REPO / "Sources/Storage/NotationFileManager.m").read_text()
start = source.index("+ (OSStatus)getDefaultNotesDirectoryRef:")
end = source.index("\n//whenever a note uses", start)
probe = (HERE / "probe.m").read_text().replace("@DIRECTORY_METHOD@", source[start:end])
with tempfile.TemporaryDirectory(prefix="nvalt-ousterhout-review-") as temporary:
    root = Path(temporary)
    harness = root / "Probe.m"
    binary = root / "Probe"
    harness.write_text(probe)
    subprocess.run(["xcrun", "clang", "-fno-objc-arc", "-Wno-deprecated-declarations",
                    "-I", str(REPO / "Sources/Application"), "-framework", "Foundation",
                    "-framework", "Carbon", str(harness), "-o", str(binary)], check=True)
    imports = subprocess.check_output(["nm", "-u", str(binary)], text=True)
    assert "_FSFindFolder" not in imports
    assert "_SecKeychain" not in imports
    for flavor, configuration in (("development", "Development"), ("release", "ForBuilding")):
        app = REPO / "build/DerivedData/Build/Products" / configuration / (identity.IDENTITIES[flavor]["name"] + ".app")
        identity.check_app(app, flavor)
        print(f"PASS: built {flavor} identity, executable, and localized names", flush=True)
        metadata = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        for copied in (False, True):
            info = dict(metadata)
            if copied:
                info["CFBundleIdentifier"] = "org.nvalt.review.copied." + flavor
            info["CFBundleExecutable"] = "Probe"
            target = root / (flavor + str(copied) + ".app") / "Contents"
            (target / "MacOS").mkdir(parents=True)
            shutil.copy2(binary, target / "MacOS/Probe")
            (target / "Info.plist").write_bytes(plistlib.dumps(info))
            subprocess.run([str(target / "MacOS/Probe"), flavor], check=True)
    print("PASS: built registration/runtime agreement, copied-bundle flavor, and default-directory dispatch", flush=True)
