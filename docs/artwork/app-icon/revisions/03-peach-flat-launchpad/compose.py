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


def compose(size=None, style="classic"):
    root = ET.Element(f"{{{SVG}}}svg", {
        "width": "1024", "height": "1024", "viewBox": "0 0 1024 1024",
    })
    ET.SubElement(root, f"{{{SVG}}}title").text = "Neo Notational V — launchpad icon"
    small = size in (32, 16)
    squircle = style == "squircle" and not small
    background = ("small/squircle-background.svg" if small else
                  "squircle-paper.svg" if squircle else "source-page.svg")
    add_layer(root, background, "background-layer" if small or squircle else "paper-layer")
    if squircle:
        # Keep the original listing text and crop the enlarged print to the paper.
        page = ET.parse(ARTWORK / "source-page.svg").getroot()
        printing = deepcopy(page.find(f".//{{{SVG}}}g[@id='source-sheet']/{{{SVG}}}g[@fill='#000']"))
        title_color = "#6d9e9a"
        for rectangle in printing.findall(f"{{{SVG}}}rect"):
            rectangle.set("y", "143")
            rectangle.set("height", "68")
            if rectangle.get("fill") == "none":
                rectangle.set("stroke", title_color)
                # Match the gap from the frame's left edge to the x=144 perforation.
                left_edge = -15 + .94 * 182
                right_edge = 880 - (left_edge - 144)
                rectangle.set("width", f"{(right_edge + 15) / .94 - 182:.6f}")
            else:
                rectangle.set("fill", title_color)
        title = printing.find(f"{{{SVG}}}text")
        title.set("fill", title_color)
        title.set("font-size", "40")
        title.set("y", "192")
        listing = printing.find(f"{{{SVG}}}text[@id='apollo-listing']")
        listing.set("font-size", "39")
        listing.set("fill", "#9b8574")
        listing.set("clip-path", "url(#squircle-listing-area)")
        definitions = ET.SubElement(printing, f"{{{SVG}}}defs")
        clip = ET.SubElement(definitions, f"{{{SVG}}}clipPath", {
            "id": "squircle-listing-area", "clipPathUnits": "userSpaceOnUse",
        })
        ET.SubElement(clip, f"{{{SVG}}}rect", {
            "x": "182", "y": "218", "width": "750", "height": "680",
        })
        baseline = 248.0
        for line in listing:
            line.set("y", f"{baseline:.1f}")
            baseline += 41.4 if line.text and line.text.strip() else 6.0
        printing.find(f"{{{SVG}}}path").set("d", "M182 905 H686")
        for footer in printing.findall(f"{{{SVG}}}text[@y='834']"):
            if footer.text == "NEO NOTATIONAL V":
                printing.remove(footer)
            else:
                footer.set("y", "923")
        paper_mask = ET.SubElement(root, f"{{{SVG}}}g", {
            "id": "printing-paper-mask", "clip-path": "url(#paper-feed-boundary)",
        })
        layer = ET.SubElement(paper_mask, f"{{{SVG}}}g", {
            "id": "printing-layer", "transform": "translate(-15 60) scale(.94)",
        })
        layer.append(printing)
    foreground = root
    if squircle:
        # Enlarge around the rocket's existing horizontal center. The crane antenna reaches
        # the paper outline; the gray deck starts below the canvas at y=1025.46.
        foreground_mask = ET.SubElement(root, f"{{{SVG}}}g", {
            "id": "launchpad-paper-mask", "clip-path": "url(#paper-feed-boundary)",
        })
        foreground = ET.SubElement(foreground_mask, f"{{{SVG}}}g", {
            "id": "launchpad-layout", "transform": "translate(-103.56 0) scale(1.08)",
        })
    # Move the tower left at small sizes so the wider rocket leaves steelwork visible.
    tower_offset = {None: 0, 48: -52, 32: -96, 16: -150}[size]
    add_layer(foreground, "launch-tower.svg", "launch-tower-layer", f"translate({tower_offset} 0)")
    rocket = f"small/saturn-v-{size}.svg" if size else "saturn-v.svg"
    # Start from the original position, with the nozzles on the launcher deck.
    rocket_transform = "translate(742 952) scale(.78) translate(-742 -980)"
    if squircle:
        # Apex of path4788 in the NASA drawing, mapped into the component canvas.
        # Scale only the rocket, keeping its antenna tip at the same position.
        placement_x, placement_scale_x = (720, 2.4366) if size == 48 else (742, 1.2183)
        tip_x = placement_x + placement_scale_x * (96.200552 - 96)
        tip_y = 506.49 + 1.2183 * (20.460945 - 401)
        rocket_transform += (f" translate({tip_x:.9f} {tip_y:.9f}) scale(2)"
                             f" translate({-tip_x:.9f} {-tip_y:.9f})")
    add_layer(foreground, rocket, "rocket-layer", rocket_transform)
    svg = ET.tostring(root, encoding="unicode")
    return "\n".join(line if line.strip() else "" for line in svg.splitlines()) + "\n"


if __name__ == "__main__":
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for style in ("classic", "squircle"):
        for size in (None, 48, 32, 16):
            prefix = "composed" if style == "classic" else "squircle"
            name = f"{prefix}-{size}" if size else prefix
            svg = compose(size, style)
            (OUTPUT / f"{name}.svg").write_text(svg)
            (OUTPUT / f"{name}.html").write_text(
                '<!DOCTYPE html><meta charset="utf-8">'
                '<style>html,body{margin:0;width:1024px;height:1024px;background:transparent}'
                'svg{display:block}</style>' + svg
            )
            if size is None:
                destination = "icon-composition.svg" if style == "classic" else "icon-squircle.svg"
                (ARTWORK / destination).write_text(svg)
    (OUTPUT / "tower-only.html").write_text(
        '<!DOCTYPE html><meta charset="utf-8">'
        '<style>html,body{margin:0;width:1024px;height:1024px;background:transparent}'
        'svg{display:block}</style>' + (ARTWORK / "launch-tower.svg").read_text()
    )
    print("Composed the classic and squircle icons at all six display sizes.")
