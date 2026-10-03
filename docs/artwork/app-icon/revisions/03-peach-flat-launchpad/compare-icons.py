#!/usr/bin/env python3
"""Show both packaged icons at their native display sizes."""

from PIL import IcnsImagePlugin, Image, ImageDraw, ImageFont

from compose import ARTWORK


ROOT = ARTWORK.parents[2]


def font(size):
    return ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", size)


def main():
    grid = Image.new("RGB", (1248, 1460), "#f5f4f1")
    draw = ImageDraw.Draw(grid)
    draw.text((48, 28), "Neo Notational V · App icon designs", font=font(28), fill="#20252b")
    draw.text((48, 70), "Two complete icon sets; unchanged drawings of the Saturn V and red launch tower.",
              font=font(15), fill="#60666e")
    draw.text((152, 116), "Classic · stacked feed paper", font=font(19), fill="#20252b")
    draw.text((688, 116), "Squircle · punched feed paper", font=font(19), fill="#20252b")
    paths = [ROOT / "Resources/Images" / name for name in ("NotalityClassic.icns", "Notality.icns")]
    with paths[0].open("rb") as classic_file, paths[1].open("rb") as squircle_file:
        icons = [IcnsImagePlugin.IcnsFile(file) for file in (classic_file, squircle_file)]
        y = 155
        for size in (512, 256, 128, 48, 32, 16):
            height = max(size + 24, 64)
            draw.text((112, y + height / 2), str(size), anchor="rm", font=font(18), fill="#20252b")
            for x, icon in zip((152, 688), icons):
                draw.rounded_rectangle((x, y, x + 512, y + height), radius=10, fill="#dfe2e5")
                rgba = icon.getimage((size, size, 1)).convert("RGBA")
                grid.paste(rgba, (x + (512 - size) // 2, y + (height - size) // 2), rgba)
            y += height + 12
    draw.text((152, y + 8), "Native ICNS images at 1×. Both sets also include Retina representations through 1024 × 1024.",
              font=font(13), fill="#60666e")
    destination = ARTWORK / "squircle-comparison.png"
    grid.crop((0, 0, 1248, y + 55)).save(destination)
    print(destination)


if __name__ == "__main__":
    main()
