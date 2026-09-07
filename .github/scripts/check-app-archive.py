#!/usr/bin/env python3
"""Check that the app archive retains executables and framework symlinks."""

import stat
import sys
import zipfile


def check_archive(path):
    prefix = "nvALT.app/Contents/"
    executables = [
        "MacOS/nvALT",
        "Frameworks/AutoHyperlinks.framework/Versions/A/AutoHyperlinks",
        "Frameworks/Sparkle.framework/Versions/A/Sparkle",
    ]
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError("The app archive contains a damaged file.")
        archive.getinfo(prefix + "Info.plist")
        for name in executables:
            mode = archive.getinfo(prefix + name).external_attr >> 16
            if not stat.S_ISREG(mode) or not mode & 0o111:
                raise ValueError("Missing executable permissions: " + name)
        for framework in ["AutoHyperlinks", "Sparkle"]:
            root = prefix + "Frameworks/" + framework + ".framework/"
            links = {"Versions/Current": "A", framework: "Versions/Current/" + framework}
            for name, target in links.items():
                mode = archive.getinfo(root + name).external_attr >> 16
                if not stat.S_ISLNK(mode) or archive.read(root + name).decode() != target:
                    raise ValueError("Missing framework symlink: " + root + name)


if __name__ == "__main__":
    check_archive(sys.argv[1])
    print("App archive checks passed.")
