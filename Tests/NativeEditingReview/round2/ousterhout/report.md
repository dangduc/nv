# Round 2 — John Ousterhout review

## Result

The Round 1 completion leak is fixed. The source body no longer has a delegate
completion policy, ordinary input remains behind `NSTextView`, and shared
storage plus shared Undo still work across two browser windows. One editor-local
display concern still crosses a process-wide boundary.

## Evidence

I ran:

```sh
python3 Tests/NativeEditingReview/round2/ousterhout/run.py
```

The injected probe passed 18 checks against the built Intel application. It
opened two real browser windows on one note, verified one shared text storage
and separate layout managers, edited in one window, and undid from the other.
It also verified that seven input and selection methods resolve to
`NSTextView`, and that the source editor's delegate no longer implements the
body completion callback.

The probe then made one source editor dark and simulated entering and leaving
it. Entering the editor changed the implementation pointer for the class method
`+[NSCursor IBeamCursor]`; a newly allocated, unrelated `NSTextView` observed
the same replacement. Leaving the source editor restored the implementation.
The complete runtime log is in `output.txt`.

## Finding

### O2 — Medium: local editor state rewrites the process-wide I-beam implementation

`LinkingEditor.m:493-517` calls `method_setImplementation` on
`+[NSCursor IBeamCursor]` whenever its background or mouse state changes.
`LinkingEditor.h:37,46` therefore stores hover state and two global method
implementations inside every editor instance. The runtime probe confirms that
hovering one dark editor changes the cursor implementation used by unrelated
text views until another `LinkingEditor` event restores it.

This is an ownership inversion: one window's view mutates a framework class for
the entire process. With multiple browser windows, whichever editor most
recently receives a state callback controls every text view. The code also
compares `NSCursor *` object pointers with `IMP` function pointers at
`LinkingEditor.m:508-514`, so the attempted current-cursor repair does not test
the values described by its comment.

Remove the `NSCursor` category, the method-implementation fields, the
mouse/background swizzle path, and its lifecycle callbacks. Keep
`setInsertionPointColor:` in `updateTextColors`; that is view-local and already
owns the actual insertion caret color. If a custom mouse cursor remains
necessary on a supported macOS version, install it through this view's cursor
rect instead of changing `NSCursor` globally. Add a runtime assertion that
changing a source editor's background and hover state cannot change the
implementation of `+[NSCursor IBeamCursor]`.

## Validation limits

The probe compared runtime ownership and method identities. It did not compare
cursor pixels or exercise every macOS release supported by the deployment
target. No production code changed during this review.
