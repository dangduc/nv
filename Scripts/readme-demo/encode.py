"""Encode captured app windows with binary GIF transparency."""
import argparse
from io import BytesIO
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageCms

repo = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--input', type=Path, default=repo / 'build/readme-demo')
parser.add_argument('--output', type=Path, help='Output directory; defaults to the capture directory.')
args = parser.parse_args()
source_root = args.input.expanduser().resolve()
root = args.output.expanduser().resolve() if args.output else source_root
root.mkdir(parents=True, exist_ok=True)
records = json.loads((source_root / 'frames.json').read_text())
with Image.open(source_root / records[0]['file']) as first:
    transform = ImageCms.buildTransform(
        ImageCms.ImageCmsProfile(BytesIO(first.info['icc_profile'])),
        ImageCms.createProfile('sRGB'), 'RGBA', 'RGBA')


def captured_frame(record):
    with Image.open(source_root / record['file']) as source:
        return ImageCms.applyTransform(source.convert('RGBA'), transform)


# Sample visible window pixels only; the discarded shadows need no palette entries.
sample_indices = sorted(set(round(i * (len(records) - 1) / 11) for i in range(12)))
samples = bytearray()
for index in sample_indices:
    for red, green, blue, alpha in captured_frame(records[index]).get_flattened_data():
        if alpha >= 128:
            samples.extend((red, green, blue))
sample = Image.frombytes('RGB', (len(samples) // 3, 1), bytes(samples))
base_palette = sample.quantize(colors=153, method=Image.Quantize.MEDIANCUT)
chromatic = bytes(channel for pixel in sample.get_flattened_data()
                  if max(pixel) - min(pixel) > 64 for channel in pixel)
color_sample = Image.frombytes('RGB', (len(chromatic) // 3, 1), chromatic)
color_palette = color_sample.quantize(colors=96, method=Image.Quantize.MEDIANCUT)
anchors = [(0, 0, 0), (255, 255, 255), (253, 233, 217),
           (245, 193, 192), (255, 239, 201), (255, 198, 0)]
colors = base_palette.getpalette()[:153 * 3] + color_palette.getpalette()[:96 * 3]
for index in range(0, len(colors), 3):
    for anchor in anchors:
        if sum((colors[index + channel] - anchor[channel]) ** 2 for channel in range(3)) < 100:
            colors[index:index + 3] = anchor
            break
palette = Image.new('P', (1, 1))
# Index 255 is transparent. Its RGB matches opaque black at index 249.
palette.putpalette(colors + [channel for anchor in anchors for channel in anchor] + [0, 0, 0])
frames = []
expected_alpha = []
for record in records:
    source = captured_frame(record)
    frame = source.convert('RGB').quantize(palette=palette, dither=Image.Dither.NONE)
    # Keep quantization from assigning an opaque pixel to the reserved index.
    frame = frame.point([index if index != 255 else 249 for index in range(256)])
    transparent = source.getchannel('A').point(lambda alpha: 255 if alpha < 128 else 0)
    frame.paste(255, mask=transparent)
    frame.info['transparency'] = 255
    frames.append(frame)
    expected_alpha.append(ImageChops.invert(transparent))

durations = [max(10, round((records[i + 1]['time'] - record['time']) * 100) * 10)
             if i + 1 < len(records) else 150 for i, record in enumerate(records)]
destination = root / 'readme-demo.gif'
# Clear each displayed frame so closing the second window leaves no stale pixels.
frames[0].save(destination, save_all=True, append_images=frames[1:], duration=durations,
               loop=0, optimize=False, disposal=2, transparency=255, background=255)

with Image.open(destination) as result:
    total = 0
    decoded = []
    for index in range(result.n_frames):
        result.seek(index)
        decoded.append((total, total + result.info['duration'], result.convert('RGBA')))
        total += result.info['duration']
    assert result.size == (1020, 780)
    assert result.info['loop'] == 0
    elapsed = 0
    for frame, alpha, duration in zip(frames, expected_alpha, durations):
        shown = next(image for start, end, image in decoded if start <= elapsed < end)
        assert ImageChops.difference(shown.getchannel('A'), alpha).getbbox() is None
        expected = frame.convert('RGBA')
        for background in ['white', '#202124']:
            matte = Image.new('RGBA', shown.size, background)
            actual_rgb = Image.alpha_composite(matte, shown).convert('RGB')
            expected_rgb = Image.alpha_composite(matte, expected).convert('RGB')
            assert ImageChops.difference(actual_rgb, expected_rgb).getbbox() is None
        elapsed += duration
    assert total == elapsed
    print(json.dumps({'path': str(destination), 'size': result.size,
                      'frames': result.n_frames, 'seconds': total / 1000,
                      'bytes': destination.stat().st_size}, indent=2))
    print(f'All {len(frames)} captured frames retain their timing and expected window mask.')
    print('Decoded frames match the palette-converted source on light and dark backgrounds.')
    for second in [4, 11, 16, 19]:
        shown = next(image for start, end, image in decoded if start <= second * 1000 < end)
        shown.save(root / f'decoded-{second}.png')
        for label, background in [('light', 'white'), ('dark', '#202124')]:
            matte = Image.new('RGBA', shown.size, background)
            Image.alpha_composite(matte, shown).convert('RGB').save(root / f'{label}-{second}.png')
