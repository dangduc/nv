#!/usr/bin/env python3
"""Inventory deletion references that still participate in the Xcode target."""

from pathlib import Path
import json
import subprocess


REPO = Path(__file__).resolve().parents[4]
PROJECT = REPO / "Notation.xcodeproj/project.pbxproj"


def audit():
    changes = subprocess.check_output(
        ["git", "diff", "--name-status", "dangduc/master...HEAD"],
        cwd=REPO,
        text=True,
    )
    deleted = [Path(line.split("\t", 1)[1]) for line in changes.splitlines()
               if line.startswith("D\t")]
    project_lines = PROJECT.read_text(errors="ignore").splitlines()
    dangling = {}
    for path in deleted:
        matches = [number for number, line in enumerate(project_lines, 1)
                   if path.name in line]
        if matches:
            dangling[path.as_posix()] = matches
    return {
        "deleted_paths": [path.as_posix() for path in deleted],
        "dangling_project_references": dangling,
    }


if __name__ == "__main__":
    print(json.dumps(audit(), indent=2, sort_keys=True))
