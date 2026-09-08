#!/usr/bin/env python3
"""Check that the app archive retains its required executables."""

import stat
import sys
import zipfile


def check_archive(path):
    prefix = "nvALT.app/Contents/"
    executables = [
        "MacOS/nvALT",
        "Resources/multimarkdown",
    ]
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError("The app archive contains a damaged file.")
        archive.getinfo(prefix + "Info.plist")
        for name in executables:
            mode = archive.getinfo(prefix + name).external_attr >> 16
            if not stat.S_ISREG(mode) or not mode & 0o111:
                raise ValueError("Missing executable permissions: " + name)



if __name__ == "__main__":
    check_archive(sys.argv[1])
    print("App archive checks passed.")
