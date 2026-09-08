#!/usr/bin/env python3
"""Exercise production parser ownership and error accumulation concurrently."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[4]
sdk = Path(subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip())
with tempfile.TemporaryDirectory(prefix="nvalt-linus-round2-") as temporary:
    for negative_control in (False, True):
        binary = Path(temporary) / ("last-error-only" if negative_control else "parser-isolation")
        command = [
            "xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13",
            "-fno-objc-arc", "-fblocks", "-Werror=unguarded-availability", "-lxml2",
            "-I", str(sdk / "usr/include/libxml2"), "-framework", "Foundation",
            "-I", str(root / "Sources/Preview"),
            str(root / "Sources/Preview/NVNoteContentSnapshot.m"),
            str(Path(__file__).with_name("parser-isolation-probe.m")), "-o", str(binary),
        ]
        if negative_control:
            command.append("-DNV_PROBE_LAST_ERROR_ONLY=1")
        subprocess.run(command, check=True)
        result = subprocess.run([str(binary)], text=True, capture_output=True, timeout=45)
        print(("Negative control: " if negative_control else "Production: ") + result.stdout.strip())
        if result.returncode != (1 if negative_control else 0):
            print(result.stderr)
            raise SystemExit("Unexpected probe outcome")
        if negative_control:
            print("PASS: the last-diagnostic-only negative control fails the same assertions")

subprocess.run([
    "xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13",
    "-fno-objc-arc", "-fblocks", "-fsyntax-only", "-Werror=unguarded-availability",
    "-Wno-deprecated-declarations", "-I", str(root / "Sources/Preview"),
    str(root / "Sources/Preview/PreviewController.m"),
], check=True)
print("PASS: renderer and preview availability checks compile for macOS 10.13")
