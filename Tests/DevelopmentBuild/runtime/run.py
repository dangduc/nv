#!/usr/bin/env python3
"""Check runtime flavor boundaries without UI, user files, or keychain access."""
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags


def method(source, signature):
    start = source.index(signature)
    following = re.search(r"\n[+-] \(", source[start + len(signature):])
    if following is None:
        raise ValueError("Missing method boundary after " + signature)
    return source[start:start + len(signature) + following.start()].strip()


prefs = (repo / "Sources/Preferences/NotationPrefs.m").read_text()
service = re.search(r"^#define KEYCHAIN_SERVICENAME .+$", prefs, re.MULTILINE).group()
signatures = (
    "- (void)forgetKeychainIdentifier", "- (const char *)setKeychainIdentifier",
    "- (SecKeychainItemRef)currentKeychainItem", "- (void)removeKeychainData",
    "- (NSData*)passwordDataFromKeychain", "- (void)setKeychainData:(NSData*)data",
    "- (void)setStoresPasswordInKeychain:(BOOL)value",
)
keychain = "\n\n".join(method(prefs, signature) for signature in signatures)
legacy = method((repo / "Sources/ImportExport/AlienNoteImporter.m").read_text(),
                "+ (void)importBlorOrHelpFilesIfNecessaryIntoNotation:")
for original, replacement in (
    ("GlobalPrefs", "NVLegacyGlobalPrefs"), ("NotationPrefs", "NVLegacyPrefs"),
    ("AlienNoteImporter", "NVLegacyImporter"), ("NotationController", "NSObject"),
):
    legacy = legacy.replace(original, replacement)
template = (Path(__file__).parent / "probe.m").read_text()
source = template.replace("@SERVICE@", service).replace("@KEYCHAIN@", keychain).replace("@LEGACY@", legacy)

with tempfile.TemporaryDirectory(prefix="nvalt-runtime-isolation-") as temporary:
    root = Path(temporary)
    harness = root / "RuntimeIsolation.m"
    binary = root / "RuntimeIsolation"
    harness.write_text(source)
    subprocess.run([
        "xcrun", "clang", "-fno-objc-arc", "-Wno-deprecated-declarations",
        *include_flags(repo), "-include", str(repo / "Config/Notation_Prefix.pch"),
        "-framework", "Cocoa", "-framework", "Carbon", "-framework", "Security",
        str(harness), "-o", str(binary),
    ], check=True)
    imports = subprocess.check_output(["nm", "-u", str(binary)], text=True)
    if "SecKeychain" in imports:
        raise RuntimeError("The probe must not link real keychain operations")
    for flavor in ("development", "release", None):
        app = root / (str(flavor) + ".app")
        executable = app / "Contents/MacOS/RuntimeIsolation"
        executable.parent.mkdir(parents=True)
        shutil.copy2(binary, executable)
        info = {"CFBundleExecutable": executable.name, "CFBundleIdentifier": "org.nvalt.runtime-probe." + str(flavor),
                "CFBundlePackageType": "APPL"}
        if flavor is not None:
            info["NVBuildFlavor"] = flavor
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        subprocess.run([str(executable), flavor or "missing"], check=True)
print("PASS: temporary paths, keychain dispatch, and automatic legacy import are isolated")
