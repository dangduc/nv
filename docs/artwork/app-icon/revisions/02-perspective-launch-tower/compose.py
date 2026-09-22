#!/usr/bin/env python3
"""Compose the paper, launch tower, and Saturn V into SVG icon previews."""

from copy import deepcopy
from pathlib import Path
import xml.etree.ElementTree as ET


ARTWORK = Path(__file__).resolve().parent
OUTPUT = ARTWORK.parents[2] / "build" / "app-icon-design"
SVG = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG)
ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")


def add_layer(composition, filename, layer_id, transform=None):
    attributes = {"id": layer_id}
    if transform:
        attributes["transform"] = transform
    layer = ET.SubElement(composition, f"{{{SVG}}}g", attributes)
    for node in ET.parse(ARTWORK / filename).getroot():
        if node.tag.rsplit("}", 1)[-1] not in ("title", "desc", "metadata"):
            layer.append(deepcopy(node))


def compose(size=None):
    root = ET.Element(f"{{{SVG}}}svg", {
        "width": "1024", "height": "1024", "viewBox": "0 0 1024 1024",
    })
    ET.SubElement(root, f"{{{SVG}}}title").text = "Neo Notational V — launchpad icon"
    add_layer(root, "source-page.svg", "paper-layer")
    # Move the tower left at small sizes so the wider rocket leaves steelwork visible.
    tower_offset = {None: 0, 48: -52, 32: -96, 16: -150}[size]
    add_layer(root, "launch-tower.svg", "launch-tower-layer", f"translate({tower_offset} 0)")
    rocket = f"small/saturn-v-{size}.svg" if size else "saturn-v.svg"
    # Fit the rocket below the crane, with the nozzles on the launcher deck.
    add_layer(root, rocket, "rocket-layer", "translate(742 952) scale(.78) translate(-742 -980)")
    return ET.tostring(root, encoding="unicode")


if __name__ == "__main__":
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for size in (None, 48, 32, 16):
        name = f"composed-{size}" if size else "composed"
        svg = compose(size)
        (OUTPUT / f"{name}.svg").write_text(svg)
        (OUTPUT / f"{name}.html").write_text(
            '<!DOCTYPE html><meta charset="utf-8">'
            '<style>html,body{margin:0;width:1024px;height:1024px;background:transparent}'
            'svg{display:block}</style>' + svg
        )
        if size is None:
            (ARTWORK / "icon-composition.svg").write_text(svg)
    (OUTPUT / "tower-only.html").write_text(
        '<!DOCTYPE html><meta charset="utf-8">'
        '<style>html,body{margin:0;width:1024px;height:1024px;background:transparent}'
        'svg{display:block}</style>' + (ARTWORK / "launch-tower.svg").read_text()
    )
    print("Composed the launchpad icon at all six display sizes.")
