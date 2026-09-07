# Editor foreground acceptance checks

The probe types URLs through the editor with clickable URLs initially on and off.
Two browser windows display each note through the shared text storage.
The windows use opposite black-on-white and white-on-black colors, then exchange colors.
The probe disables, enables, and disables clickable URLs in each case.

Bitmap assertions require visible ordinary text and URL glyphs in the expected colors.
The probe also checks the preferred link appearance, link boundaries, and actual temporary search highlights.
Attributed-text comparisons and archive roundtrips check that display changes preserve note attributes.
Separate layout managers keep each window's colors and search highlights local.

After a Development build, run this command from the repository root:

```sh
python3 Tests/Regression/native-rendering/run.py
```

To save the editor bitmap captures, use this command:

```sh
python3 Tests/Regression/native-rendering/run.py --artifacts build/pr-review/native-rendering
```

The runner accepts `--app PATH` for a different app build.
The preserved review app provides a negative control:

```sh
python3 Tests/Regression/native-rendering/run.py --app build/NativeUIReview/round1/nvALT.app
```

The negative control must fail on a dark editor with clickable URLs disabled.
Its URL bitmap contains no glyphs in the expected white foreground.

Each run acquires `build/pr-review/gui.lock` and uses a copied app with a unique preferences domain.
Notes, support files, and temporary files use a temporary directory.
The probe skips normal startup services and external editor initialization.
The runner limits the app process to 90 seconds.

The fixture selects the explicit color scheme before it assigns per-window colors.
Automatic appearance callbacks can otherwise replace those colors during a capture.
Native activation checks require the intended key window and active browser before note creation or capture.
The fixture also waits up to two seconds for each browser session to contain the note before selection.
Diagnostic lines record activation, library ownership, query, selection, and editor state.
