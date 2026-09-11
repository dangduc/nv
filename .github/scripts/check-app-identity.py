#!/usr/bin/env python3
"""Check the built app identity and its Launch Services registrations."""

import argparse
import os
from pathlib import Path
import plistlib
import subprocess


IDENTITIES = {
    "release": {
        "name": "nvALT",
        "identifier": "net.elasticthreads.nv",
        "signature": "N†l√",
        "schemes": ["nvalt", "nv"],
        "rank": "Default",
        "shortcut": "V",
    },
    "development": {
        "name": "nvALT Development",
        "identifier": "net.elasticthreads.nv.development",
        "signature": "NvDv",
        "schemes": ["nvalt-dev", "nv-dev"],
        "rank": "None",
        "shortcut": "",
    },
}


def check_identity(info, flavor):
    expected = IDENTITIES[flavor]
    fields = {
        "CFBundleName": expected["name"],
        "CFBundleDisplayName": expected["name"],
        "CFBundleExecutable": expected["name"],
        "CFBundleIdentifier": expected["identifier"],
        "CFBundleSignature": expected["signature"],
        "NVBuildFlavor": flavor,
    }
    for key, value in fields.items():
        if info.get(key) != value:
            raise ValueError(f"{flavor} {key} must be {value!r}; found {info.get(key)!r}.")
    expected_urls = [{
        "CFBundleURLName": expected["identifier"],
        "CFBundleURLSchemes": expected["schemes"],
    }]
    if info.get("CFBundleURLTypes") != expected_urls:
        raise ValueError(f"Unexpected {flavor} URL registrations.")
    documents = info.get("CFBundleDocumentTypes", [])
    if len(documents) != 2 or any(item.get("LSHandlerRank") != expected["rank"] for item in documents):
        raise ValueError(f"Unexpected {flavor} document handler rank.")
    services = info.get("NSServices", [])
    if len(services) != 1:
        raise ValueError(f"Expected one {flavor} selection service.")
    service = services[0]
    if (service.get("NSPortName") != expected["name"] or
            service.get("NSMenuItem") != {"default": expected["name"] + ": New Note from Selection"} or
            service.get("NSKeyEquivalent") != {"default": expected["shortcut"]}):
        raise ValueError(f"Unexpected {flavor} selection service identity.")


def check_app(path, flavor):
    path = Path(path)
    expected_name = IDENTITIES[flavor]["name"]
    if path.name != expected_name + ".app":
        raise ValueError(f"Unexpected {flavor} application filename: {path.name}.")
    with (path / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    check_identity(info, flavor)
    executable = path / "Contents/MacOS" / info["CFBundleExecutable"]
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise ValueError(f"Missing executable: {executable}.")
    for strings in (path / "Contents/Resources").glob("*.lproj/InfoPlist.strings"):
        data = strings.read_bytes()
        try:
            localized = plistlib.loads(data)
        except plistlib.InvalidFileException:
            converted = subprocess.run(["plutil", "-convert", "xml1", "-o", "-", str(strings)],
                                       check=True, stdout=subprocess.PIPE)
            localized = plistlib.loads(converted.stdout)
        for key in ("CFBundleName", "CFBundleDisplayName"):
            if key in localized and localized[key] != expected_name:
                raise ValueError(f"Unexpected localized {flavor} {key}: {strings}.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("flavor", choices=IDENTITIES)
    arguments = parser.parse_args()
    check_app(arguments.app, arguments.flavor)
    print(f"{arguments.flavor.capitalize()} application identity checks passed.")
