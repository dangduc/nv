# Round 2: ownership and public cleanup calls

This agent review uses a John Ousterhout-inspired perspective. It does not represent a review by John Ousterhout.

No actionable finding. The existing public cleanup method protects its callers from character-edit timing. The tested attachment paths match the documented ownership boundary.

The earlier probe adapted the controller's attachment ordering. This round executes the exact production `_setCurrentNote:finishingEditing:` method. It also extracts `textDidBeginEditing:`, `textDidChange:`, the source observer, and four editor methods. Native `NSTextStorage`, `NSLayoutManager`, notifications, delayed selectors, and run loops supply the editing behavior.

The candidate passes 26 checks on macOS 26.5.2, running Intel code through Rosetta. Compilation produced no warnings. The final run tested `feef9bd`. Its four production files match `c2209e2`. Their hashes remained unchanged during the run; `manifest.json` records both hashes and the tested commit.

The checks cover these caller contracts:

- Foreign editing notifications leave this editor unchanged. The actual begin-editing callback clears its highlights and then invokes note creation.
- Attribute-only transactions permit synchronous cleanup. They do not advance the source generation.
- Actual begin-editing and change callbacks inside a character transaction defer native layout removal. Create, commit, and update callbacks still execute.
- The character observer and text-change callback each advance the generation. Their cleanup requests converge after editing completes.
- Selecting the same note executes the production early return. Its existing cleanup remains pending and runs once.
- Switching notes with `finishingEditing:NO` skips the finish callback. The actual method transfers storage and session attachment callbacks.
- An old note's delayed cleanup cannot erase new highlights. Notifications from detached storage do not invalidate the new note.
- Selecting no note retires the session, observer, and pending cleanup. Later edits to the detached storage leave the empty editor unchanged.

Three deliberate defects fail the intended assertions:

| Removed behavior | Failed assertions | Consequence |
| --- | ---: | --- |
| Cleanup before attachment | 3 | Pending cleanup survives switching and can run against the empty editor. |
| New storage observer registration | 2 | Character processing stops advancing the attached editor's generation. |
| Character-edit guard | 2 | Public controller callbacks mutate layout during the open transaction. |

The control runner requires explicit assertion failures. It rejects exceptions and process errors as evidence of control sensitivity.

Run:

```sh
python3 Tests/SourceBackspaceReview/round2/ousterhout/run.py
```

The probe tests the controller methods through an adapter. Fake notes and sessions supply storage and record callbacks. `finishEditing` records its invocation; it does not operate an input method. The probe does not instantiate a browser, render pixels, or test the service that produces async search results. It does not prove attachment safety during a reentrant switch inside an unfinished character transaction. The user's macOS 13.7.8 environment remains unavailable.
