#!/usr/bin/env python3
"""Prepare the existing squircle artwork for the system's icon mask."""

import importlib.util
from pathlib import Path
import xml.etree.ElementTree as ET

from compose import ARTWORK, OUTPUT, SVG, compose


if __name__ == "__main__":
    spec = importlib.util.spec_from_file_location("build_icon", ARTWORK / "build-icon.py")
    renderer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(renderer)
    root = ET.fromstring(compose(style="squircle"))
    # Icon Composer supplies the enclosure and outside margin. Expand the existing
    # paper to the full canvas, retaining the artwork inside its 32..992 bounds.
    root.set("viewBox", "32 32 960 960")
    root.find(f".//{{{SVG}}}path[@id='paper-squircle']").set(
        "d", "M0 0 H1024 V1024 H0 Z")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    source = OUTPUT / "modern-artwork.svg"
    source.write_text(ET.tostring(root, encoding="unicode"))
    destination = ARTWORK / "NeoNotationalV.icon/Assets/artwork.png"
    destination.parent.mkdir(parents=True, exist_ok=True)
    renderer.render(Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
                    source, 1024, destination)
    print(destination)
