# Native UI validation

## Corrected build

Production revision `12936fe` passed the full regression suite and the multiwindow suite.
The environment was macOS 13.7.8, Xcode 15.2, and the macOS 14.2 SDK.
The x86_64 Development build ran under Rosetta with the documented deployment overrides.

The optional full-screen run passed 71 native UI checks on an unlocked desktop.
AppKit confirmed entry and exit while both panes retained their vertical stack.
This supersedes the earlier locked-desktop limitation recorded during initial validation.

```sh
mkdir -p build/NativeUIReview/current-captures
NV_UI_FULL_SCREEN=1 NV_UI_ARTIFACTS="$PWD/build/NativeUIReview/current-captures" \
  python3 Tests/Regression/native-ui/run.py
```

The captures contain only synthetic notes from the disposable test library.

![Corrected light appearance](screenshots/corrected-light.png)

![Corrected dark appearance with a white notes list](screenshots/corrected-dark.png)

## Limits

Live sync services and external editor applications require separate manual checks.
This validation does not establish behavior on other macOS versions.
Ventura logs a layout warning inside AppKit's adaptive search toolbar item.
The resize, control, and full-screen checks passed despite that warning.
