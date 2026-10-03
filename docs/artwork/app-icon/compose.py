#!/usr/bin/env python3
"""Compose Flowing Fanfold icon masters without cropping the launchpad."""

import base64
from pathlib import Path
import xml.etree.ElementTree as ET

from PIL import Image

ARTWORK = Path(__file__).resolve().parent
OUTPUT = ARTWORK.parents[2] / "build" / "app-icon-design"
SVG = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG)
BACKGROUND = "#f3f0ea"
SQUIRCLE = ("M512 32 C948.8 32 992 75.2 992 512 "
            "C992 948.8 948.8 992 512 992 "
            "C75.2 992 32 948.8 32 512 C32 75.2 75.2 32 512 32 Z")


def master_for_size(size):
    if size in (16, 32):
        return "micro.png"
    return "compact.png" if size == 48 else "full.png"


def compose(size=None, style="classic", modern=False):
    root = ET.Element(f"{{{SVG}}}svg", {
        "width": "1024", "height": "1024", "viewBox": "0 0 1024 1024",
    })
    ET.SubElement(root, f"{{{SVG}}}title").text = "Neo Notational V — Flowing Fanfold launchpad"
    if style == "squircle" or modern:
        ET.SubElement(root, f"{{{SVG}}}path", {
            "id": "icon-background", "fill": BACKGROUND,
            "d": "M0 0 H1024 V1024 H0 Z" if modern else SQUIRCLE,
        })
    source = ARTWORK / "fanfold" / master_for_size(size)
    with Image.open(source) as image:
        # Faint generated alpha outside the illustration does not set icon scale.
        # Pixel data remains unchanged; fit the solid subject with a safe margin.
        bounds = image.getchannel("A").point(lambda alpha: 255 if alpha >= 64 else 0).getbbox()
        width, height = image.size
    left, top, right, bottom = bounds
    # Keep the full tip, crane, paper loop and raised platform inside the system mask.
    extent = 944 if style == "classic" else (832 if modern else 800)
    if size in (16, 32, 48):
        extent = 968 if style == "classic" else 880
    scale = min(extent / (right - left), extent / (bottom - top))
    x = (1024 - (right - left) * scale) / 2 - left * scale
    y = (1024 - (bottom - top) * scale) / 2 - top * scale
    foreground = root
    if style == "squircle" and not modern:
        definitions = ET.SubElement(root, f"{{{SVG}}}defs")
        clip = ET.SubElement(definitions, f"{{{SVG}}}clipPath", {"id": "icon-boundary"})
        ET.SubElement(clip, f"{{{SVG}}}path", {"d": SQUIRCLE})
        foreground = ET.SubElement(root, f"{{{SVG}}}g", {"clip-path": "url(#icon-boundary)"})
    ET.SubElement(foreground, f"{{{SVG}}}image", {
        "id": "fanfold-artwork", "x": f"{x:.6f}", "y": f"{y:.6f}",
        "width": f"{width * scale:.6f}", "height": f"{height * scale:.6f}",
        "href": "data:image/png;base64," + base64.b64encode(source.read_bytes()).decode("ascii"),
    })
    return ET.tostring(root, encoding="unicode") + "\n"


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
                '<style>html,body{margin:0;background:transparent}svg{display:block}</style>' + svg)
            if size is None:
                filename = "icon-composition.svg" if style == "classic" else "icon-squircle.svg"
                (ARTWORK / filename).write_text(svg)
    print("Composed full, compact and micro Flowing Fanfold icons.")
