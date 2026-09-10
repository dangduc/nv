Round 2 of 3 — Linus Torvalds-inspired correctness review. This is an agent review, not a review by Linus Torvalds.

**No actionable finding.** The cleanup guard handles mixed character and attribute edits. Direct callers share this guard, so they need no duplicate storage-state checks.

I wrote a new AppKit probe for notification ordering. It extracts four exact production methods: the storage observer, invalidation, cleanup, and range publication. An `NSObject` adapter supplies editor ownership. Storage, layout managers, edit notifications, and the run loop use AppKit.

The candidate passed 43 assertions on Intel through Rosetta. It also passed 43 assertions on arm64 with AddressSanitizer and UndefinedBehaviorSanitizer. Compilation used `-Wall -Wextra -Werror` and produced no warnings. Neither sanitizer reported an error.

- Attribute-only edits retain the accepted source generation and existing highlights. Direct cleanup works during either the Will or Did notification.
- A nested batch combines attributes and character deletion. Both edit flags remain set during both notification phases. Direct cleanup and publication make no layout writes during that interval.
- An observer adds an attribute during Will processing. Cleanup preserves that attribute and the shortened source. It makes one background-removal write after processing finishes.
- An attribute-only edit after a character edit neither repeats nor resets invalidation. A foreign storage notification leaves the editor state unchanged.
- A publication with no highlight color still clears old backgrounds and cancels pending cleanup. Explicit cleanup permits immediate receiver destruction; pumping the run loop causes no later callback.

Two negative controls failed at the intended assertions:

| Deliberate defect | Result |
| --- | --- |
| Test the edit mask with equality instead of a bitwise check | Four failures; mixed edits cause premature layout writes. |
| Invalidate for attribute-only notifications | Seven failures; accepted generation and backgrounds change without a source edit. |

These cases extend the first round's range tests. They establish why the guard must test the character bit, and why attribute-only notifications should remain outside invalidation.

Run `python3 Tests/SourceBackspaceReview/round2/torvalds/run.py`. See [the probe](probe.m.in), [sanitizer output](candidate-native-sanitize-output.txt), and [manifest](manifest.json). The manifest records both architectures, controls, HEAD, and SHA-256 hashes for four production files. All four hashes matched before and after execution. HEAD was `feef9bd95ceb4f3b05d2a5cb00622c1b269ea4d9`; production remains the `c2209e2` fix.

Limits: the probe creates no browser, text view, or window. It does not paint glyphs or invoke an input method. It models the direct cleanup callers through exact editor methods; it does not execute those browser methods. ASan leak detection is disabled. Destruction assertions check the retained delayed-selector lifetime only. The host is macOS 26.5.2; the user's macOS 13.7.8 environment remains untested. I changed no production files.
