#!/usr/bin/env python3
"""Round-2 deletion and build-integrity audit for native source editing."""

from pathlib import Path
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


repo = Path(__file__).resolve().parents[4]
here = Path(__file__).resolve().parent


def check(condition, description):
    if not condition:
        print("FAIL:", description)
        raise SystemExit(1)
    print("PASS:", description)


def occurrences(token, paths):
    matches = []
    for path in paths:
        if not path.is_file():
            continue
        for number, line in enumerate(path.read_text(errors="ignore").splitlines(), 1):
            if token in line:
                matches.append(f"{path.relative_to(repo)}:{number}")
    return matches


subprocess.run(["git", "diff", "--check"], cwd=repo, check=True)
print("PASS: working-tree diff has no whitespace errors")

project = (repo / "Notation.xcodeproj/project.pbxproj").read_text()
check("LinkingEditor_Indentation" not in project,
      "deleted indentation category has no Xcode project reference")

editor_path = repo / "Sources/Editor/LinkingEditor.m"
editor_header = repo / "Sources/Editor/LinkingEditor.h"
editor = editor_path.read_text()
removed_editor_selectors = (
    "deleteBackward:", "insertNewline:", "insertTab:", "insertBacktab:",
    "performKeyEquivalent:", "keyDown:", "selectionRangeForProposedRange:",
    "insertText:", "rangeForUserCompletion", "pasteMarkdownLink:",
    "insertLink:", "strikethroughNV:", "shiftLeftAction:", "shiftRightAction:",
)
for selector in removed_editor_selectors:
    stem = selector.split(":", 1)[0]
    active_definition = any(
        line.lstrip().startswith("- (") and re.search(rf"\b{re.escape(stem)}\b", line)
        for line in editor.splitlines()
    )
    check(not active_definition, f"LinkingEditor does not override {selector}")

localization = repo / "Resources/Localization"
xibs = []
for locale in ("en", "de", "fr", "it", "pt-PT", "zh"):
    root = localization / f"{locale}.lproj"
    for name in ("MainMenu.xib", "BrowserWindow.xib", "Preferences.xib"):
        path = root / name
        ET.parse(path)
        xibs.append(path)
check(len(xibs) == 18, "all localized editor/preferences XIBs are well-formed XML")

with tempfile.TemporaryDirectory(prefix="nvalt-r2-torvalds-xibs-") as temporary:
    for xib in xibs:
        output = Path(temporary) / f"{xib.parent.name}-{xib.stem}.nib"
        result = subprocess.run(
            ["xcrun", "ibtool", "--errors", "--warnings", "--compile", str(output), str(xib)],
            cwd=repo, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
        check(result.returncode == 0, f"ibtool compiles {xib.relative_to(repo)}")

with tempfile.TemporaryDirectory(prefix="nvalt-r2-torvalds-native-") as temporary:
    binary = Path(temporary) / "native-tab-defaults"
    subprocess.run(
        ["xcrun", "clang", "-fno-objc-arc", "-framework", "Cocoa", "-o", str(binary),
         str(here / "native-tab-defaults.m")],
        cwd=repo, check=True,
    )
    native = subprocess.run([str(binary)], cwd=repo, check=True,
                            stdout=subprocess.PIPE, text=True)
    print(native.stdout, end="")
print("PASS: fresh NSTextView has no explicit paragraph-style/tab-width override")

source_files = [path for path in (repo / "Sources").rglob("*")
                if path.suffix in {".h", ".m", ".c", ".mm"}]
tab_tokens = ("NumberOfSpacesInTab", "numberOfSpacesInTab", "noteBodyParagraphStyle",
              "_bodyFontIsMonospace", "setDefaultTabInterval")
tab_matches = {token: occurrences(token, source_files) for token in tab_tokens}
tab_matches = {token: matches for token, matches in tab_matches.items() if matches}
if tab_matches:
    print("FINDING P2: hidden legacy tab-width behavior still overrides native NSTextView")
    for token, matches in tab_matches.items():
        print(f"  {token}: {', '.join(matches)}")
else:
    print("PASS: legacy tab-width preference and paragraph-style override are removed")

generator_paths = {
    repo / "Sources/Preferences/NVPasswordGenerator.h",
    repo / "Sources/Preferences/NVPasswordGenerator.m",
}
generator_refs = occurrences("NVPasswordGenerator", source_files)
external_generator_refs = [match for match in generator_refs
                           if not match.startswith("Sources/Preferences/NVPasswordGenerator.")]
project_generator_refs = [f"Notation.xcodeproj/project.pbxproj:{number}"
                          for number, line in enumerate(project.splitlines(), 1)
                          if "NVPasswordGenerator" in line]
if any(path.exists() for path in generator_paths) and not external_generator_refs:
    print("FINDING P3: NVPasswordGenerator is compiled but has no production caller")
    for match in generator_refs + project_generator_refs:
        print(" ", match)
else:
    print("PASS: no caller-free NVPasswordGenerator source is shipped")

orphaned_localizations = (
    "Use Automatic Text Replacement", "Insert Link", "New Password...",
    "Insert New Password", "Strikethrough",
)
for key in orphaned_localizations:
    production = occurrences(f'@"{key}"', source_files)
    localized = occurrences(key, sorted(localization.glob("*.lproj/Localizable.strings")))
    if localized and not production:
        locale_count = len({match.split(":", 1)[0] for match in localized})
        print(f"FINDING P3: localization key has no production use: {key} ({locale_count} locales)")

minimum_evidence = "\n".join(
    (repo / path).read_text(errors="ignore")
    for path in ("README.markdown", ".github/workflows/macos.yml")
)
check("MACOSX_DEPLOYMENT_TARGET=10.13" in minimum_evidence,
      "documented and CI deployment target is macOS 10.13")
compat_tokens = ("IsLeopardOrLater", "IsLionOrLater", "prepareTextFinderPreLion")
compat_matches = {token: occurrences(token, (editor_path, editor_header)) for token in compat_tokens}
compat_matches = {token: matches for token, matches in compat_matches.items() if matches}
dead_members = ("selectedRangeDuringFind", "stringDuringFind", "noteDuringFind",
                "windowBecameOrResignedMain")
dead_matches = {token: occurrences(token, (editor_path, editor_header)) for token in dead_members}
dead_matches = {token: matches for token, matches in dead_matches.items() if matches}
if compat_matches or dead_matches:
    print("FINDING P3: LinkingEditor retains unsupported find compatibility and dead state")
    for token, matches in {**compat_matches, **dead_matches}.items():
        print(f"  {token}: {', '.join(matches)}")
else:
    print("PASS: unsupported finder compatibility and dead editor state are removed")

double_retain = "textFinder=[[[NSTextFinderalloc]init]retain]"
if double_retain in editor.replace(" ", ""):
    print("FINDING P2: supported NSTextFinder allocation is retained twice and released once")
else:
    print("PASS: NSTextFinder ownership has no alloc-plus-retain leak")

subprocess.run(
    [sys.executable, str(repo / "Tests/SourceEditing/run.py"), "--compile-only"],
    cwd=repo, check=True,
)
print("PASS: native source-editing integration probe compiles")
