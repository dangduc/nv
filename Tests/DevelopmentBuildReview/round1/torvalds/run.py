#!/usr/bin/env python3
"""Bounded native metadata review; never launch either app or register handlers."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
PRODUCTS = REPO / "build/DerivedData/Build/Products"
DEVELOPMENT = PRODUCTS / "Development/nvALT Development.app"
RELEASE = PRODUCTS / "ForBuilding/nvALT.app"
LANGUAGES = ("en", "de", "fr", "it", "pt-PT", "zh")


def run(command, **kwargs):
    return subprocess.run(command, check=True, timeout=45, **kwargs)


with tempfile.TemporaryDirectory(prefix="nvalt-torvalds-review-") as temporary:
    root = Path(temporary)
    baseline = root / "Baseline.app"
    (baseline / "Contents").mkdir(parents=True)
    raw = subprocess.check_output(["git", "show", "bd74bf3:Config/Info.plist"], cwd=REPO, timeout=15).decode()
    for key, value in {"EXECUTABLE_NAME": "nvALT", "PRODUCT_NAME": "nvALT",
                       "PRODUCT_BUNDLE_IDENTIFIER": "net.elasticthreads.nv",
                       "MACOSX_DEPLOYMENT_TARGET": "10.13"}.items():
        raw = raw.replace("$(" + key + ")", value).replace("${" + key + "}", value)
    assert "$(" not in raw and "${" not in raw
    (baseline / "Contents/Info.plist").write_bytes(plistlib.dumps(plistlib.loads(raw.encode())))
    common = [str(REPO / "Notation.xcodeproj/project.pbxproj"), str(DEVELOPMENT), str(RELEASE), str(baseline)]
    for architecture in ("arm64", "x86_64"):
        binary = root / ("probe-" + architecture)
        run(["xcrun", "clang", "-arch", architecture, "-fno-objc-arc", "-Wall", "-Wextra",
             "-framework", "Foundation", "-framework", "CoreFoundation", str(HERE / "probe.m"), "-o", str(binary)])
        print("ARCHITECTURE:", architecture, flush=True)
        for language in LANGUAGES:
            run([str(binary), *common, language, "-AppleLanguages", "(" + language + ")"])

    # Negative control: a stale localized name must fail the native lookup.
    mutant = root / "nvALT Development.app"
    contents = mutant / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    shutil.copy2(DEVELOPMENT / "Contents/Info.plist", contents / "Info.plist")
    executable = contents / "MacOS/nvALT Development"
    executable.write_text("not executed\n")
    executable.chmod(0o755)
    localization = contents / "Resources/en.lproj"
    localization.mkdir(parents=True)
    (localization / "InfoPlist.strings").write_bytes(plistlib.dumps({"CFBundleName": "nvALT"}))
    invalid = subprocess.run([str(binary), common[0], str(mutant), *common[2:], "en", "-AppleLanguages", "(en)"],
                             timeout=15, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert invalid.returncode != 0 and "localized identity CFBundleName" in invalid.stderr, invalid
    print("PASS: stale localized-name negative control was rejected", flush=True)
print("PASS: 24 built-bundle native checks, 12 baseline comparisons, and one negative control", flush=True)
