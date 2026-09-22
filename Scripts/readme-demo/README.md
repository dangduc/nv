# README demo recording

These scripts preserve the capture and encoding tools used for `docs/screenshots/readme-demo.gif`.
They record fuzzy searches, result selection, and two browser windows with disposable Org notes.

## Requirements

- An active macOS desktop with at least 1020 × 780 points of usable display space.
- Full Xcode and an unsigned Intel Development app built from the current checkout.
- Rosetta on Apple Silicon.
- Python 3.10 or later and Pillow 12.2.0 for encoding.

The capture uses the default app at `build/DerivedData/Build/Products/Development/Neo Notational V Development.app`.
See the [repository build instructions](../../README.markdown#build-and-run).
After a Development build, run the desktop suites required by [AGENTS.md](../../AGENTS.md).

## Capture and encode

Run these commands from the repository root.
Install Pillow in your Python environment:

```sh
python3 -m pip install 'Pillow==12.2.0'
```

Record the interactions:

```sh
python3 Scripts/readme-demo/run-capture.py
```

Keep the desktop available until the recording finishes.
The capture takes about 20 seconds after app launch.
It copies the app into a temporary directory and uses separate notes and preferences.
The capture app exits after the recording.
The runner uses the shared desktop-test lock and timeout cleanup.

Encode the recording:

```sh
python3 Scripts/readme-demo/encode.py
```

Both scripts default to `build/readme-demo` for output.
The capture writes `frames/*.png`, `frames.json`, and `launch-services.log`.
The encoder writes `readme-demo.gif` and still previews on transparent, white, and charcoal backgrounds.
It checks the decoded frames against the captured frames after color, palette, and transparency conversion.
It also checks the recorded timing and window masks.

Inspect the GIF and previews before replacing the documentation asset:

```sh
cp build/readme-demo/readme-demo.gif docs/screenshots/readme-demo.gif
```

Update the capture details in [the screenshot notes](../../docs/screenshots/README.md).
Frame counts, duration, and file size can vary between recordings.

## Alternate paths

Use `--app` for a different Development app and `--output` for a different capture directory:

```sh
python3 Scripts/readme-demo/run-capture.py \
  --app '/path/to/Neo Notational V Development.app' \
  --output build/readme-demo-new
python3 Scripts/readme-demo/encode.py \
  --input build/readme-demo-new \
  --output build/readme-demo-encoded
```

The scripts overwrite their output files on each run.
The encoder can reuse existing frames without launching the app.

## Implementation notes

`run-capture.py` reuses the native-controls test harness in `Tests/Regression/native-controls`.
It compiles `prefix.h`, `capture.inc`, `helpers.inc`, and `fixtures.inc` into a temporary library loaded by the copied app.
The capture uses Launch Services to give the sample windows keyboard focus.
Changes to app internals or the test harness can require updates to these scripts.

The encoder uses a shared palette, converts the capture profile to sRGB, and preserves timing to the nearest 10 milliseconds.
GIF supports binary transparency. Pixels with alpha below 128 become transparent, which removes the soft shadows outside the windows.
The encoder clears each frame before the next frame to prevent stale pixels when a window closes.
These tools require a desktop session and do not run in CI.
