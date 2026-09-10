#!/usr/bin/env python3
"""Probe the final source-editor abstraction boundary."""
from pathlib import Path
import re
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]


def structural_checks() -> None:
    implementation = (REPO / "Sources/Editor/LinkingEditor.m").read_text()
    header = (REPO / "Sources/Editor/LinkingEditor.h").read_text()
    forbidden = [
        "- (void)keyDown:", "- (void)deleteBackward:", "- (void)insertTab:",
        "- (void)insertText:", "- (void)complete:", "method_setImplementation",
        "WhiteIBeamCursor", "NumberOfSpacesInTab",
    ]
    for token in forbidden:
        assert token not in implementation, f"retired policy returned: {token}"
    assert "shouldChangeTextInRange:" in implementation
    assert "- (void)didChangeText" in implementation
    assert "changedRange" in header
    assert "addLinkAttributesForRange:changedRange" in implementation

    # This public method has no production caller. Keep the count as evidence of
    # the remaining surface, without making it the primary review finding.
    sources = "\n".join(
        path.read_text(errors="ignore")
        for path in (REPO / "Sources").rglob("*") if path.suffix in {".m", ".h"}
    )
    assert len(re.findall(r"highlightRangesTemporarily", sources)) == 3


def main() -> int:
    structural_checks()
    with tempfile.TemporaryDirectory(prefix="nvalt-ousterhout-r3-") as temporary:
        root = Path(temporary)
        executable = root / "edited-range-probe"
        subprocess.run(
            [
                "xcrun", "clang", "-fno-objc-arc", "-framework", "Cocoa",
                "-o", str(executable), str(HERE / "edited-range-probe.m"),
            ],
            check=True,
        )
        result = subprocess.run(
            [str(executable)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, check=False,
        )
        (HERE / "output.txt").write_text(result.stdout)
        print(result.stdout, end="")
        passed = "OUSTERHOUT ROUND 3 RANGE PROBE PASSED (9 checks)" in result.stdout
        return 0 if result.returncode == 0 and passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
