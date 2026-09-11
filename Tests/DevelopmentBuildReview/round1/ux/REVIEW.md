# Round 1 UX and workflow review

Reviewed production commit: `2dbfd46`; baseline: `bd74bf3`.

No actionable finding from the bounded checks below.

## Hypotheses and evidence

1. Generated or copied note links could leave Development and operate on release notes.
   The native probe extracts the production `uniqueNoteLink`, wiki-link generation,
   and `clickedOnLink:atIndex:` methods. Both flavors passed 17 checks each.
   Development generates `nvalt-dev` links and sends those clicks to its local controller.
   Release generates `nvalt` links and sends those clicks to its local controller.
   Command-click creates a `make` URL with the current flavor's scheme.
   Copied `nvalt` links retain their existing local handling in both flavors.
   Explicit `nv` and `nv-dev` aliases reach the superclass. These target an explicit
   application scheme, so this observation is not counted as an isolation defect.

2. The renamed Development product could break the documented build/run workflow.
   The README and AGENTS launch commands both quote the renamed bundle path.
   That path, its executable, and its bundle name match the built Development product.
   The release product retains its documented name and executable.
   No stale launch command was found in these two current entry-point documents.

3. Fixed nvALT labels could make Development indistinguishable during normal use.
   The read-only fixture records authored About, Hide, and Quit titles for all six
   `MainMenu.xib` localizations. They still contain release-era names.
   The production browser-title method also uses the note title, or `nvALT` when empty.
   These facts alone do not establish a runtime defect: AppKit may replace the
   application-menu title, and the build adds a distinct bundle name and DEV Dock badge.
   No GUI run was added while integration owned the desktop. No finding is asserted
   for authored labels without a confirmed ambiguous runtime workflow.

## Reproduction

```sh
python3 Tests/DevelopmentBuildReview/round1/ux/run.py
```

The command passed and wrote `results.json`. The output contains 34 native checks,
the routing matrix, documented-path checks, and authored menu/title evidence.

## Limits

The probe starts no `NSApplication`, loads no nibs, launches no URLs, and reads no
user notes or preferences. Recording collaborators replace the editor's window,
preferences object, local controller, and superclass link handler. Encoding helpers
use fixture implementations; escaping correctness is outside this review.

The test confirms production URL construction and branch selection. It does not
test LaunchServices handler selection, AppKit menu substitution, contextual Open
Link actions, hidden-Dock status menus, or interaction with a real release library.
This reviewer changed only files in `Tests/DevelopmentBuildReview/round1/ux`.
