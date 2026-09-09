# User Scheme checks

Build the Development app, then run these checks from an active macOS desktop:

```sh
python3 Tests/Regression/user-schemes/run.py --artifacts build/user-schemes-artifacts
```

The runner copies the app and uses temporary notes and a unique preferences domain.
It seeds the three existing color keys, then launches the copied app twice.
It also compiles the production appearance method for macOS 10.13 and tests its older-system fallback.

The checks cover:

- Existing custom colors stay in the light palette. Dark defaults are independent.
- Both browser windows share one note, with opposite effective appearances.
- Native appearance changes refresh the palette, search highlights, links, and caret.
- All six visible Fonts & Colors wells dispatch their configured actions.
- Editing either palette updates the correct inactive browser without changing the other palette.
- Search backgrounds composite the raw highlight alpha over each browser background.
- Source attributes and Undo history remain unchanged.
- Both custom palettes and the existing User Scheme choice survive relaunch.

The fixture sets each test window's Aqua or Dark Aqua appearance.
This exercises AppKit appearance callbacks without changing the user's system setting.
The drawing checks inspect real layout attributes. They do not compare screenshot pixels.
The optional screenshots contain only disposable notes and Settings.

The compatibility check forces the fallback on the current host using native AppKit appearance objects.
It checks appearance restoration after success and exceptions, color ownership, and fixed schemes.
This simulation does not replace testing on an older macOS installation.
Run its negative controls separately:

```sh
python3 Tests/Regression/user-schemes/compatibility.py --negative-controls
```
