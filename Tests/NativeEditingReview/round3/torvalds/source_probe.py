#!/usr/bin/env python3
"""Find source-editing deletion residue without guessing from binary output."""

from pathlib import Path
import json


REPO = Path(__file__).resolve().parents[4]
SOURCES = REPO / "Sources"
EDITOR = SOURCES / "Editor/LinkingEditor.m"
HEADER = SOURCES / "Editor/LinkingEditor.h"


def occurrences(token, roots):
    matches = []
    for root in roots:
        paths = root.rglob("*") if root.is_dir() else (root,)
        for path in paths:
            if not path.is_file():
                continue
            try:
                lines = path.read_text(errors="ignore").splitlines()
            except OSError:
                continue
            for number, line in enumerate(lines, 1):
                if token in line:
                    matches.append(f"{path.relative_to(REPO)}:{number}")
    return matches


def audit():
    editor = EDITOR.read_text()
    header = HEADER.read_text()
    removed_preference_tokens = (
        "AutoSuggestLinks", "AutoIndentsNewLines", "AutoFormatsListBullets",
        "TabKeyIndents", "CheckSpellingInNoteBody", "TextReplacementInNoteBody",
        "UseSoftTabs", "NumberOfSpacesInTab", "UseAutoPairing",
        "UsesMarkdownCompletions", "UseSmartInsertDelete", "RTLKey",
    )
    removed_selector_order_entries = (
        "-[LinkingEditor isContinuousSpellCheckingEnabled]",
        "-[LinkingEditor readablePasteboardTypes]",
        "-[LinkingEditor acceptableDragTypes]",
    )
    order_files = (REPO / "Config/Notation.freqorder", REPO / "Config/Notation.launchorder")
    stale_order = {symbol: occurrences(symbol, order_files)
                   for symbol in removed_selector_order_entries}
    stale_order = {symbol: matches for symbol, matches in stale_order.items() if matches}

    highlight_occurrences = occurrences("highlightRangesTemporarily", (SOURCES,))
    orphan_highlight_helper = (
        "- (void)highlightRangesTemporarily:" in editor
        and "- (void)highlightRangesTemporarily:" in header
        and len(highlight_occurrences) == 3
        and all(match.startswith("Sources/Editor/LinkingEditor.")
                for match in highlight_occurrences)
    )

    compatibility_tokens = ("prepareTextFinderPreLion", "IsLeopardOrLater", "IsLionOrLater",
                            "MAC_OS_X_VERSION_MAX_ALLOWED")
    return {
        "removed_preference_tokens": {
            token: occurrences(token, (SOURCES,))
            for token in removed_preference_tokens
            if occurrences(token, (SOURCES,))
        },
        "stale_order_entries": stale_order,
        "orphan_highlight_helper": orphan_highlight_helper,
        "highlight_helper_occurrences": highlight_occurrences,
        "unsupported_editor_compatibility": {
            token: occurrences(token, (EDITOR, HEADER))
            for token in compatibility_tokens
            if occurrences(token, (EDITOR, HEADER))
        },
        "finder_alloc_plus_retain": "textFinder=[[[NSTextFinderalloc]init]retain]"
                                     in editor.replace(" ", ""),
    }


if __name__ == "__main__":
    print(json.dumps(audit(), indent=2, sort_keys=True))
