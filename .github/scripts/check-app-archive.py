#!/usr/bin/env python3
"""Check required executables, syntax resources, and search notices in the app archive."""

import argparse
import stat
import struct
import zipfile


def check_architecture(data, arch, name):
    # CI publishes separate thin 64-bit builds. Inspect the archive payload,
    # not its filename or the machine which happened to produce it.
    expected_cpu = {"x86_64": 0x01000007, "arm64": 0x0100000c}[arch]
    if len(data) < 32 or struct.unpack_from("<II", data) != (0xfeedfacf, expected_cpu):
        raise ValueError(f"Expected a thin {arch} Mach-O executable: {name}")


def check_archive(path, arch=None):
    prefix = "Neo Notational V.app/Contents/"
    executables = [
        "MacOS/Neo Notational V",
        "Resources/multimarkdown",
        "Resources/nv-org-preview",
    ]
    syntax_resources = [
        "Resources/Syntax/json.scm",
        "Resources/Syntax/html.scm",
        "Resources/Syntax/markdown.scm",
        "Resources/Syntax/markdown-inline.scm",
        "Resources/Syntax/ThirdPartyNotices.txt",
    ]
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError("The app archive contains a damaged file.")
        archive.getinfo(prefix + "Info.plist")
        for name in executables:
            mode = archive.getinfo(prefix + name).external_attr >> 16
            if not stat.S_ISREG(mode) or not mode & 0o111:
                raise ValueError("Missing executable permissions: " + name)
            if arch:
                check_architecture(archive.read(prefix + name), arch, name)
        for name in syntax_resources:
            try:
                info = archive.getinfo(prefix + name)
            except KeyError as error:
                raise ValueError("Missing syntax resource: " + name) from error
            if not stat.S_ISREG(info.external_attr >> 16) or not archive.read(info).strip():
                raise ValueError("Syntax resource must be a nonempty regular file: " + name)
        for name in ("FZF-GPL-3.0.txt", "FZF-MIT.txt", "UTF8PROC.txt"):
            resource = "Resources/SearchLicenses/" + name
            try:
                info = archive.getinfo(prefix + resource)
            except KeyError as error:
                raise ValueError("Missing search notice: " + resource) from error
            if not stat.S_ISREG(info.external_attr >> 16) or not archive.read(info).strip():
                raise ValueError("Search notice must be a nonempty regular file: " + resource)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive")
    parser.add_argument("--arch", choices=("x86_64", "arm64"))
    args = parser.parse_args()
    check_archive(args.archive, args.arch)
    print("App archive checks passed.")
