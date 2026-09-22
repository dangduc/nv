#!/usr/bin/env python3
"""Render the SVG designs and package the application's ICNS resource."""

import argparse
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import time

from PIL import IcnsImagePlugin, Image

from compose import ARTWORK, OUTPUT


ROOT = ARTWORK.parents[2]
# Logical size, display scale, ICNS resource type.
REPRESENTATIONS = (
    (16, 1, b"is32"), (16, 2, b"ic11"),
    (32, 1, b"il32"), (32, 2, b"ic12"),
    (48, 1, b"ih32"),
    (128, 1, b"ic07"), (128, 2, b"ic13"),
    (256, 1, b"ic08"), (256, 2, b"ic14"),
    (512, 1, b"ic09"), (512, 2, b"ic10"),
)


def render(chrome, source, pixels, destination):
    """Render at the target resolution, using an isolated browser profile."""
    with tempfile.TemporaryDirectory(prefix="neo-icon-render-") as temporary:
        work = Path(temporary)
        page = work / "icon.html"
        screenshot = work / "icon.png"
        page.write_text(
            '<!DOCTYPE html><meta charset="utf-8">'
            '<style>html,body{margin:0;background:transparent}'
            f'svg{{display:block;width:{pixels}px;height:{pixels}px}}</style>'
            + source.read_text()
        )
        with (work / "chrome.log").open("w") as log:
            process = subprocess.Popen([
                str(chrome), "--headless", "--disable-gpu", "--no-first-run",
                "--no-default-browser-check", "--disable-background-networking",
                "--disable-component-update", "--disable-sync",
                f"--user-data-dir={work / 'profile'}",
                "--default-background-color=00000000", "--force-device-scale-factor=1",
                "--window-size=1024,1024", "--hide-scrollbars",
                f"--screenshot={screenshot}", page.as_uri(),
            ], stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 30
                while time.monotonic() < deadline:
                    if screenshot.exists():
                        try:
                            with Image.open(screenshot) as image:
                                image.load()
                                image.convert("RGBA").crop((0, 0, pixels, pixels)).save(destination)
                            return
                        except OSError:
                            pass  # Chrome can still be writing the screenshot.
                    if process.poll() is not None:
                        break
                    time.sleep(.1)
                raise RuntimeError(f"Chrome did not render {destination.name}; see output:\n"
                                   + (work / "chrome.log").read_text())
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)


def chunk(kind, data):
    return struct.pack(">4sI", kind, len(data) + 8) + data


def legacy_rgb(image):
    """Encode the 16px, 32px, and 48px entries as ICNS RLE literal runs."""
    result = bytearray()
    for channel in image.convert("RGB").split():
        data = channel.tobytes()
        for offset in range(0, len(data), 128):
            run = data[offset:offset + 128]
            result.extend(bytes([len(run) - 1]) + run)
    return bytes(result)


def build(chrome, destination, style):
    stem = "NeoNotationalV-" + style
    iconset = OUTPUT / f"{stem}.iconset"
    iconset.mkdir(exist_ok=True)
    entries = []
    expected = {}
    for size, scale, kind in REPRESENTATIONS:
        suffix = "@2x" if scale == 2 else ""
        png = iconset / f"icon_{size}x{size}{suffix}.png"
        prefix = "composed" if style == "classic" else "squircle"
        source = OUTPUT / (f"{prefix}-{size}.svg" if size in (16, 32, 48) else f"{prefix}.svg")
        render(chrome, source, size * scale, png)
        with Image.open(png) as image:
            rgba = image.convert("RGBA")
            if not rgba.getchannel("A").getbbox():
                raise RuntimeError(f"Empty icon: {png}")
            expected[(size, size, scale)] = rgba
            if scale == 1 and size in (16, 32, 48):
                alpha_kind = {16: b"s8mk", 32: b"l8mk", 48: b"h8mk"}[size]
                entries.extend([chunk(kind, legacy_rgb(rgba)), chunk(alpha_kind, rgba.getchannel("A").tobytes())])
            else:
                entries.append(chunk(kind, png.read_bytes()))
        print(f"Rendered {style}: {size}px at {scale}x", flush=True)

    # Keep the logical 16px and 32px designs distinct from larger pixel dimensions.
    # ImageIO can alias PNG-based 32px entries to the 16px Retina image.
    # Legacy RGB/mask pairs preserve the distinct 1x drawings in the native decoder.
    table = chunk(b"TOC ", b"".join(entry[:8] for entry in entries))
    data = chunk(b"icns", table + b"".join(entries))
    candidate = OUTPUT / f"{stem}.icns"
    candidate.write_bytes(data)
    with candidate.open("rb") as file:
        decoded = IcnsImagePlugin.IcnsFile(file)
        if set(decoded.itersizes()) != set(expected):
            raise RuntimeError("ICNS representation set does not match the rendered designs")
        for size, image in expected.items():
            if decoded.getimage(size).convert("RGBA").tobytes() != image.tobytes():
                raise RuntimeError(f"ICNS pixels changed during packaging: {size}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.resolve() != candidate.resolve():
        destination.write_bytes(data)
    print(f"Checked all {len(expected)} representations; wrote {destination}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chrome", type=Path,
                        default=Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"))
    parser.add_argument("--style", choices=("classic", "squircle", "both"), default="both",
                        help="Build both bundled icons by default")
    parser.add_argument("--output", type=Path,
                        help="Output ICNS path; requires a single --style")
    args = parser.parse_args()
    if not args.chrome.is_file():
        parser.error("Chrome was not found; set --chrome to its executable")
    if args.output and args.style == "both":
        parser.error("--output requires --style classic or --style squircle")
    subprocess.run([sys.executable, str(ARTWORK / "compose.py")], check=True)
    styles = ("classic", "squircle") if args.style == "both" else (args.style,)
    for style in styles:
        filename = "NotalityClassic.icns" if style == "classic" else "Notality.icns"
        build(args.chrome, args.output or ROOT / "Resources/Images" / filename, style)
