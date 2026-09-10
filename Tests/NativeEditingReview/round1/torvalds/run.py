#!/usr/bin/env python3
"""Audit the native-editor cleanup for active and orphaned legacy behavior."""

from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET


repo = Path(__file__).resolve().parents[4]


def check(condition, description):
    if not condition:
        print("FAIL:", description)
        raise SystemExit(1)
    print("PASS:", description)


def occurrences(token, paths):
    matches = []
    for path in paths:
        if path.is_file():
            for number, line in enumerate(path.read_text(errors="ignore").splitlines(), 1):
                if token in line:
                    matches.append(f"{path.relative_to(repo)}:{number}")
    return matches


subprocess.run(["git", "diff", "--check", "dangduc/master...HEAD"], cwd=repo, check=True)
print("PASS: branch diff has no whitespace errors")

project = (repo / "Notation.xcodeproj/project.pbxproj").read_text()
check("LinkingEditor_Indentation" not in project,
      "deleted indentation category has no Xcode project reference")

removed_editor_selectors = (
    "deleteBackward:", "insertNewline:", "insertTab:", "insertBacktab:",
    "performKeyEquivalent:", "keyDown:",
    "selectionRangeForProposedRange:", "insertText:",
    "rangeForUserCompletion", "pasteMarkdownLink:", "insertLink:",
    "strikethroughNV:", "shiftLeftAction:", "shiftRightAction:",
)
editor_implementation = (repo / "Sources/Editor/LinkingEditor.m").read_text()
for selector in removed_editor_selectors:
    # Objective-C return types sit between '- (' and the selector.  The explicit
    # regex-free checks below catch both direct action names and normal methods.
    active_definition = any(
        line.lstrip().startswith("- (") and selector.split(":", 1)[0] in line
        for line in editor_implementation.splitlines()
    )
    check(not active_definition, f"LinkingEditor does not override {selector}")

active_xibs = sorted((repo / "Resources/Localization").glob("*.lproj/MainMenu.xib"))
active_xibs += sorted((repo / "Resources/Localization").glob("*.lproj/Preferences.xib"))
check(len(active_xibs) == 12, "all six active MainMenu and Preferences localizations were found")
for xib in active_xibs:
    ET.parse(xib)
print("PASS: all changed active XIBs are well-formed XML")

removed_ui_fragments = (
    "changedTabBehavior:", "changedSpellChecking:", "changedAutoSuggestLinks:",
    "changedSoftTabs:", "changedAutoPairing:", "changedRTL:",
    "tabKeyRadioMatrix", "checkSpellingButton", "autoSuggestLinksButton",
    "softTabsButton", "autoPairButton", "rtlButton",
)
active_ui = "\n".join(path.read_text(errors="ignore") for path in active_xibs)
for fragment in removed_ui_fragments:
    check(fragment not in active_ui, f"active XIBs omit {fragment}")

source_files = [
    path for path in (repo / "Sources").rglob("*")
    if path.suffix in {".h", ".m", ".c", ".mm"}
]
orphaned_helpers = (
    "tabbifiedStringWithNumberOfSpaces",
    "numberOfLeadingSpacesFromRange",
    "firstNumberFromStringWithinRange",
    "isPairedCharacterWithMatchString",
    "replaceTabsWithSpacesOfWidth",
    "listBulletsCharacterSet",
    "NVHiddenBulletIndentAttributeName",
)
orphaned = {}
for token in orphaned_helpers:
    matches = occurrences(token, source_files)
    if matches:
        orphaned[token] = matches

if orphaned:
    print("FINDING: legacy editor helpers remain without production call sites")
    for token, matches in orphaned.items():
        print(f"  {token}: {', '.join(matches)}")
else:
    print("PASS: legacy tab/list/pair helper declarations and definitions are removed")

orphan_nib = repo / "Resources/Localization/fr.lproj/Preferences_small.nib/designable.nib"
tracked = subprocess.run(
    ["git", "ls-files", "--error-unmatch", str(orphan_nib.relative_to(repo))],
    cwd=repo, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
).returncode == 0
if tracked:
    nib_text = orphan_nib.read_text(errors="ignore")
    stale = [fragment for fragment in
             ("Soft tabs", "checkSpellingButton", "autoSuggestLinksButton")
             if fragment in nib_text]
    check("Preferences_small" not in project,
          "legacy Preferences_small nib is not an active Xcode resource")
    if stale:
        print("FINDING: tracked orphan Preferences_small nib retains removed controls: "
              + ", ".join(stale))
else:
    print("PASS: obsolete Preferences_small nib is not tracked")

subprocess.run(
    [sys.executable, str(repo / "Tests/SourceEditing/run.py"), "--compile-only"],
    cwd=repo, check=True,
)
print("PASS: native source-editing integration probe compiles")
