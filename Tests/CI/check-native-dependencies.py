#!/usr/bin/env python3
"""Execute rebuilt arm64 crypto and preview helpers against fixed references."""
import json
from pathlib import Path
import platform
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def check(directory):
    if platform.machine() != "arm64":
        raise RuntimeError("Native dependency checks require an Apple Silicon process.")
    executable = directory / "crypto-check"
    subprocess.run(["xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=11.0",
                    "-I" + str(directory / "include"), str(HERE / "native-crypto.c"),
                    str(directory / "libcrypto.a"), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
    fixtures = json.loads((HERE / "fixtures/previews.json").read_text())
    for fixture in fixtures:
        source = ROOT / fixture["source"]
        expected = HERE / "fixtures" / fixture["expected"]
        result = subprocess.run([str(directory / fixture["helper"]), *fixture["arguments"]],
                                input=source.read_bytes(), capture_output=True, check=True, timeout=15)
        if result.stdout != expected.read_bytes():
            raise ValueError("Native preview differs from the checked Intel reference: " + fixture["expected"])
        print("PASS: native preview matches Intel reference: " + fixture["expected"])


if __name__ == "__main__":
    check(Path(sys.argv[1]).resolve())
