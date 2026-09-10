### Round 2 review — John Ousterhout perspective

I ran `python3 Tests/NativeEditingReview/round2/ousterhout/run.py` against the
built Intel app. All 18 checks passed. The Round 1 completion leak is fixed:
seven ordinary input and selection methods resolve to `NSTextView`, the body
delegate has no completion hook, and a native edit plus cross-window Undo kept
two editors and their note model consistent.

**Medium — keep cursor state inside the editor boundary.**
`LinkingEditor.m:493-517` calls `method_setImplementation` on
`+[NSCursor IBeamCursor]` based on one editor's hover and background state. The
probe made one editor dark, simulated a mouse enter, and observed the class
method's implementation change process-wide; a newly allocated unrelated
`NSTextView` inherited that replacement until another source-editor event
restored it. This lets the most recent browser window control the cursor used by
every text view. Lines 508-514 also compare cursor object pointers with `IMP`
function pointers, so the repair condition does not inspect the values its
comment describes.

Remove the cursor category, the two `IMP` fields, and the global swizzle path.
Keep the existing view-local `setInsertionPointColor:` call. If a custom mouse
cursor is still required, install it through the editor's cursor rect. Preserve
this probe as a regression assertion that editor state cannot change the
implementation of `+[NSCursor IBeamCursor]`.

Validation limit: the probe checked runtime ownership and shared editing, but
did not compare cursor pixels across supported macOS releases.
