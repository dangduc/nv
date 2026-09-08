#!/usr/bin/env python3
"""Check the menu action anchors in every localized source nib."""
from pathlib import Path
import xml.etree.ElementTree as ET

repo = Path(__file__).resolve().parents[4]
count = 0
for path in sorted((repo / "Resources/Localization").glob("*.lproj/MainMenu.xib")):
    root = ET.parse(path).getroot()
    parents = {child: parent for parent in root.iter() for child in parent}
    anchors = [a for a in root.iter("action") if a.get("selector") == "toggleNoteBodyPreviews:"]
    assert len(anchors) == 1, (path, "missing or duplicated anchor")
    item = parents[parents[anchors[0]]]
    assert item.tag == "menuItem"
    view_item = parents[parents[parents[item]]]
    assert view_item.tag == "menuItem" and view_item.get("tag") == "99", (path, view_item.attrib)
    word_count = [a for a in root.iter("action") if a.get("selector") == "toggleWordCount:"]
    assert len(word_count) == 1, (path, "word-count action ambiguity")
    print(f"PASS {path.parent.name}: View action anchor and word-count action")
    count += 1
assert count == 6
print(f"LOCALIZED MENU AUDIT PASSED ({count} source nibs)")
