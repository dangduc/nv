#!/usr/bin/env python3
"""Check required executables, syntax resources, and search notices in the app archive."""

import stat
import sys
import zipfile


def check_archive(path):
    prefix = "nvALT.app/Contents/"
    executables = [
        "MacOS/nvALT",
        "Resources/multimarkdown",
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
    check_archive(sys.argv[1])
    print("App archive checks passed.")
