# Round 2: hidden-window state transitions

This review uses a Kyle Kingsbury-inspired state-transition lens. It does not represent a review by Kyle Kingsbury.

Baseline: `755bc8b849547e6714ffaa22fbb339ad65008393`, compared with `878961a`.
Production code remains unchanged since `2e3f75e794b668024cf54597110f13ccf2aff97a`.

No actionable introduced defect was found within this scope.

Round one explicitly delivered appearance callbacks to two surviving windows.
This round adds application-level appearance changes, hidden windows, complete fixture controller disposal, and window recreation with one retained tag cache.

## Executable evidence

Run this command with access to the active desktop session:

```sh
python3 Tests/NotesListAppearanceReview/round2/kingsbury/run.py --negative-controls
```

The native arm64 fixture passed **1,081 checks** in each ordinary and `NSZombieEnabled=YES` run.
Each run used 24 controller generations and 96 application-level appearance transitions.
All three deliberate regression controls failed their intended assertions.
The compiler emitted no diagnostics.
The host used macOS 26.5.2 and Xcode 26.6.

The runner extracts the production list-construction prefix, `NVBrowserContentView` class, `browserAppearanceChanged`, `updateColorScheme`, and tag-cache method.
It also compiles the production rounded-rectangle utility.
The controller fixture supplies native windows, split views, scroll views, tables, and an editor.
The editor callback and main-view background setter are fixed collaborators.

Each window briefly enters the window list with zero alpha, then stays ordered out.
The fixture changes `NSApplication.appearance` within its own process. It does not change the user's system settings.
No fixture code calls either production appearance callback directly.

## Results

| Boundary | Observed result |
| --- | --- |
| Create a hidden window after an application appearance change | Its first draw uses the current list background and the corresponding retained tag image. |
| Change Aqua, Dark Aqua, and both high-contrast appearances while the window stays hidden | AppKit delivers the production callback and requests a list redraw. |
| Allow a brief run-loop turn before explicit appearance resolution | All 96 callbacks arrive before the fixture resolves view appearances or requests a bitmap draw. |
| Draw the hidden table after each transition | Its native drawing context resolves the expected background and tag fill colors. |
| Destroy each controller, drain its autorelease pool, and create the next controller | The cache retains two distinct color images. Equal colors reuse images across controller generations. |
| Retain the former production content view after detachment and controller disposal | A later appearance change reaches no destroyed controller. The zombie run reports no deallocated-object message. |
| Change appearance on an observed detached subclass | AppKit delivers two callbacks. The production callback safely follows its nil-window route. |

The runner records disposal of all 24 fixture controllers before their successors are created.
The hidden windows never become visible during their appearance transitions.
These results support the existing view-to-window ownership route at `Sources/Browser/AppController_BrowserUI.m:22`.

Three deliberate mutations establish detection boundaries:

- Dropping production callback forwarding fails the automatic delivery assertion.
- Restoring the explicit Aqua appearance fails the inherited list appearance assertion.
- Removing the resolved color from the tag key fails the assertion for different color images.

Logs and generated sources remain under `build/NotesListAppearanceReview/round2/kingsbury/`.

## Limits

The sandbox blocks application-to-window appearance propagation on this host, even after a run-loop turn.
The successful runs used desktop access. The sandbox result supplies no application defect claim.

These changes originate from an application appearance override. They do not establish delivery from a physical macOS appearance toggle.
Bitmap captures use each native view's backing dimensions. This round checks colors in the drawing context, not individual glyph pixels or visual contrast.

The fixture supplies controller construction and disposal. It does not instantiate the production application owner, browser nibs, editing sessions, or library persistence.
Its sample table draws production tag images without the complete note-cell path.
The initial-controller retention policy and complete application teardown remain outside this result.

The review did not launch an Intel application or use personal notes.
The host's existing Intel startup stall prevents the full desktop suites.
