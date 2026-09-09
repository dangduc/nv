# Round 1: design and ownership review

Perspective: John Ousterhout's emphasis on clear interfaces and ownership. This is an independent review, not a claim to represent him.

Reviewed commit: `6b8d67514f4fc5bc2e9fca22816a32f30f59fb1c`, compared with upstream `89d9abe`.

## Findings

No actionable defect found in the reviewed ownership and focus boundaries.

The field remains a browser-owned interaction through a toolbar item and one container. Moving its layout into the container does not add a controller, mutable shared state, or an asynchronous focus operation. The existing controller teardown releases this ownership graph.

## Executable evidence

Run from the repository root in an active desktop session:

```sh
python3 Tests/TitlebarReview/round1/ousterhout/run.py
```

The runner extracts unmodified production toolbar setup, delegate methods, search focus, and controller `dealloc`. It compiles those methods with the actual `DualField.m` implementation into a native arm64 AppKit probe. The fixture initializes the field through the production coder path. It holds no extra retain on the field when toolbar setup starts.

The probe uses `build/pr-review/gui.lock` and opens blank test windows. It does not open note storage or personal notes.

| Case | Result |
| --- | --- |
| Production, eight setup/focus/teardown cycles | 120 assertions passed; eight field and eight wrapper deallocations; exit 0. |
| Negative control: remove only `[searchContainer release]` | 13 assertions passed, then field teardown assertion failed; exit 1. |

Each production cycle verifies these contracts:

- The legacy wrapper leaves the content view and releases after the autorelease pool drains.
- The field survives migration and belongs to the owning window through the toolbar container.
- Browser delegates remain local, and native search actions have no implicit note target.
- Hiding the title preserves its semantic value, including after a normal title update.
- The toolbar contains only Search and refuses the removed NewNote identifier.
- Search focus completes before the method returns. A later body focus request survives event processing and preserves the query.
- Controller teardown releases the migrated field once.

Relevant production locations: `Sources/Browser/AppController_BrowserUI.m:335`, `:345`, `:356`, `:362`, and `:386`; `Sources/Browser/AppController.m:1931`, `:1966`, and `:2013`.

## Source record

| Input | SHA-256 |
| --- | --- |
| `Sources/Browser/AppController_BrowserUI.m` | `6a179cb93dfe10052bb894b077cb969a1a748862646adbe35cec4b4cdcf1a33a` |
| `Sources/Browser/AppController.m` | `46a9c9f6f0aee838d547dd7b0ef17fa80f97978e1e951ffa0dca91229dac67be` |
| `Sources/UI/DualField.m` | `6617a4b656f5d55587ac0ee374148efdbc906772c9f3e2ace1ab9a205dd6f9c8` |
| `Sources/Browser/AppController.h` | `d222dcbaec7b680dbcbc46022b100c0e75c7d7b166110d87134be1e9e65acbb4` |
| Extracted production methods | `f760ee90e66488d1c1c84172083a1190c7ab31af911b83ce0b7ebf5e8ff4dde2` |
| Negative-control methods | `40e972c2804dfdb917b7fbdb133f9b3d3595056bf853b09f762b5f8776e08d5d` |

Generated compiler logs, run logs, extracted methods, and JSON source records remain under `build/TitlebarReview/round1/ousterhout/`.

## Limits and fixture corrections

Executed on macOS 26.5.2 (25F84), Xcode 26.6 (17F113). This probe does not validate Intel app startup, note model changes, live resize, VoiceOver, or older macOS releases. It explicitly detaches the window toolbar before controller release to isolate the controller/item/view graph from AppKit's window retention. Unrelated `cancelMultiTagEditing` and `discardViewer` calls have empty fixture implementations; their state is absent.

The first sandboxed launch could not connect to AppKit and timed out. The successful run used desktop access. An initial assertion expected wrapper deallocation immediately after removal. AppKit defers that release until the autorelease pool drains, so the fixture now checks removal first and deallocation after draining. This was a fixture assumption, not a production finding.

No production changes requested by this review.
