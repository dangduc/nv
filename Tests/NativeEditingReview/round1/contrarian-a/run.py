#!/usr/bin/env python3
"""Audit native editor defaults and localized menu residue."""
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

repo = Path(__file__).resolve().parents[4]
review = Path(__file__).resolve().parent
localization = repo / "Resources" / "Localization"
editor_source = (repo / "Sources" / "Editor" / "LinkingEditor.m").read_text()
project_source = (repo / "Notation.xcodeproj" / "project.pbxproj").read_text()

with tempfile.TemporaryDirectory(prefix="native-edit-review-") as temp:
    binary = Path(temp) / "native-defaults"
    subprocess.run([
        "xcrun", "clang", "-fno-objc-arc", "-framework", "Cocoa",
        "-o", str(binary), str(review / "native_defaults.m")
    ], check=True)
    defaults = subprocess.check_output([str(binary)], text=True)

expected_actions = {
    "Check Spelling as You Type": "toggleContinuousSpellChecking:",
    "Smart Copy/Paste": "toggleSmartInsertDelete:",
    "Smart Quotes": "toggleAutomaticQuoteSubstitution:",
    "Smart Dashes": "toggleAutomaticDashSubstitution:",
    "Text Replacement": "toggleAutomaticTextReplacement:",
}

problems = []
menus_checked = 0
explicit_spell_correction = 0
for path in sorted(localization.glob("*.lproj/MainMenu.xib")):
    root = ET.parse(path).getroot()
    locale = path.parent.name
    menus_checked += 1

    editor = next((node for node in root.iter("textView")
                   if node.attrib.get("customClass") == "LinkingEditor"), None)
    if editor is None:
        problems.append(f"{locale}: missing LinkingEditor")
    elif editor.attrib.get("spellingCorrection") == "YES":
        explicit_spell_correction += 1

    for item in root.iter("menuItem"):
        title = item.attrib.get("title")
        if title in expected_actions:
            actions = [a.attrib.get("selector") for a in item.iter("action")]
            if actions != [expected_actions[title]]:
                problems.append(f"{locale}: {title!r} actions are {actions!r}")

        submenu = item.find("menu")
        if submenu is not None and any(
            action.attrib.get("selector") == "fixFileEncoding:"
            for action in submenu.iter("action")
        ):
            children = submenu.find("items")
            entries = list(children) if children is not None else []
            kinds = [(entry.tag, entry.attrib.get("title"),
                      entry.attrib.get("isSeparatorItem")) for entry in entries]
            if len(entries) >= 2 and all(entry.attrib.get("isSeparatorItem") == "YES"
                                         for entry in entries[:2]):
                problems.append(f"{locale}: status Format starts with adjacent separators: {kinds!r}")

shortcut_claims = ("⌘[", "⌘]", "⌥Tab", "⌘T", "⌘B", "⌘I", "⌘Y", "⌘←", "⌘→")
help_checked = 0
for path in sorted(localization.glob("*.lproj/Excruciatingly Useful Shortcuts.nvhelp")):
    plain = subprocess.check_output(["textutil", "-convert", "txt", "-stdout", str(path)], text=True)
    compact = "".join(plain.split())
    help_checked += 1
    present = [claim for claim in shortcut_claims if claim in compact]
    if present:
        problems.append(f"{path.parent.name}: shipped help still claims removed shortcuts {present!r}")

print(defaults, end="")
print(f"localizedMenusChecked={menus_checked}")
print(f"localizedEditorsMatchingNativeSpellingCorrection={explicit_spell_correction}")
print(f"localizedHelpFilesChecked={help_checked}")
for problem in problems:
    print(f"PROBLEM: {problem}")

separator_residue = [p for p in problems if "adjacent separators" in p]
stale_help = [p for p in problems if "shipped help still claims" in p]
removed_implementations = (
    "- (void)shiftLeftAction:", "- (void)shiftRightAction:",
    "- (void)bold:", "- (void)italic:", "- (void)strikethroughNV:",
    "- (BOOL)performKeyEquivalent:", "- (void)keyDown:",
)
assert menus_checked == 6
assert explicit_spell_correction == 6
assert len(separator_residue) == 6
assert help_checked == 6
assert len(stale_help) == 6
assert "automaticSpellingCorrection=1" in defaults
assert all(method not in editor_source for method in removed_implementations)
assert "Excruciatingly Useful Shortcuts.nvhelp in Resources" in project_source
print("removedShortcutImplementations=7")
print("PASS: reproduced stale shipped help and localized status-menu residue")
