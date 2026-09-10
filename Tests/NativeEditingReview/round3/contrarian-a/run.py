#!/usr/bin/env python3
"""Round 3 contrarian audit of native source-editor cleanup."""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
LOCALIZATIONS = sorted((ROOT / "Resources/Localization").glob("*.lproj"))
REMOVED = {
    "changedSpellChecking:",
    "changedTabBehavior:",
    "changedSoftTabs:",
    "changedAutoPairing:",
    "changedRTL:",
    "changedAutoSuggestLinks:",
    "changedStyledTextBehavior:",
}


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)
    print(f"PASS: {message}")


def compile_xibs() -> None:
    with tempfile.TemporaryDirectory(prefix="nv-round3-contrarian-a-") as temp:
        output = Path(temp)
        count = 0
        for localization in LOCALIZATIONS:
            for name in ("MainMenu.xib", "BrowserWindow.xib", "Preferences.xib"):
                source = localization / name
                destination = output / f"{localization.stem}-{name}.nib"
                result = subprocess.run(
                    ["xcrun", "ibtool", "--compile", str(destination), str(source)],
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                )
                check(result.returncode == 0, f"{source.relative_to(ROOT)} compiles")
                count += 1
        check(count == 18, "all 18 affected localized XIBs were compiled")


def audit_xibs() -> None:
    check(len(LOCALIZATIONS) == 6, "all six application localizations are present")
    for localization in LOCALIZATIONS:
        source_editors = []
        for name in ("MainMenu.xib", "BrowserWindow.xib"):
            root = ET.parse(localization / name).getroot()
            editors = [node for node in root.iter("textView") if node.get("customClass") == "LinkingEditor"]
            check(len(editors) == 1, f"{localization.stem}/{name} has one source editor")
            source_editors.extend(editors)
        for editor in source_editors:
            check(editor.get("richText") == "NO", f"{localization.stem} source editor is plain text")
            check(editor.get("importsGraphics") == "NO", f"{localization.stem} source editor rejects graphics")
            check(editor.get("smartInsertDelete") == "YES", f"{localization.stem} source editor uses native smart insert/delete")

        preferences = ET.parse(localization / "Preferences.xib").getroot()
        selectors = {action.get("selector") for action in preferences.iter("action")}
        check(not (selectors & REMOVED), f"{localization.stem} Preferences has no removed editing actions")


def audit_source() -> None:
    implementation = (ROOT / "Sources/Editor/LinkingEditor.m").read_text()
    header = (ROOT / "Sources/Editor/LinkingEditor.h").read_text()
    preferences = (ROOT / "Sources/Preferences/GlobalPrefs.m").read_text()

    match = re.search(
        r"- \(void\)changeColor:\(id\)sender\s*\{(?P<body>.*?)\n\}",
        implementation,
        re.DOTALL,
    )
    check(match is not None, "LinkingEditor still overrides the standard changeColor: command")
    executable = "\n".join(
        line.split("//", 1)[0].strip() for line in match.group("body").splitlines()
    ).strip()
    check(executable == "return;", "LinkingEditor changeColor: is only a no-op return")
    check("changeColor:" not in header, "the no-op color override is not part of LinkingEditor API")
    check("[self setRichText:NO]" in implementation, "LinkingEditor enforces plain-text mode")
    check("[self setUsesFontPanel:NO]" in implementation, "LinkingEditor keeps font choice in app preferences")

    for token in (
        "CheckSpellingInNoteBodyKey",
        "TabKeyIndentsKey",
        "AutoSuggestLinksKey",
        "UseSoftTabsKey",
        "UseAutoPairing",
        "RTLKey",
    ):
        check(token not in preferences, f"removed preference token {token} remains absent")


def run_probe() -> None:
    with tempfile.TemporaryDirectory(prefix="nv-round3-contrarian-a-probe-") as temp:
        executable = Path(temp) / "probe"
        compile_result = subprocess.run(
            [
                "xcrun",
                "clang",
                "-fno-objc-arc",
                "-framework",
                "Cocoa",
                str(HERE / "probe-body.m"),
                "-o",
                str(executable),
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        check(compile_result.returncode == 0, "AppKit color-command probe compiles")
        result = subprocess.run(
            [str(executable)], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
        )
        (HERE / "output.txt").write_text(result.stdout)
        sys.stdout.write(result.stdout)
        check(result.returncode == 0, "AppKit color-command probe passes")


def main() -> int:
    audit_source()
    audit_xibs()
    compile_xibs()
    run_probe()
    print("RESULT: one P3 cleanup finding; no additional behavioral defect found")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, ET.ParseError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
