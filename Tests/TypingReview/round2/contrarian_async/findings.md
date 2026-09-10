# Round 2 — contrarian async review

No confirmed new defect in this scope at `5eda58b`.

The concern was that a captured word-count request could outlive the UI's interest, or that demand arriving after capture could be lost. I tested the production scheduler, link extraction, word counting, session snapshot/publication methods, and browser observer methods.

Run:

```sh
python3 Tests/TypingReview/round2/contrarian_async/run.py
```

Result: **21 assertions passed across six transition cases**, exit code 0. The runner records its source hash, compiler, command, platform, and HEAD in `environment.json`. Generated code and executable reside in `build/TypingReview/round2/contrarian_async`.

Evidence in `probe.m` and `output.txt`:

- Enabling word count while a links-only snapshot is in flight creates follow-up demand. The current count appears after that work completes.
- Removing the final interested client before completion suppresses word publication. Reenabling it after completion computes and publishes the count once.
- Removing one of two observers leaves the remaining observer functional. The removed, hidden label stays unchanged. A notification for another session does not change the active label.
- One hundred off/on transitions during an in-flight request preserve the accepted count. The coalesced follow-up captures one nil snapshot, then stops. The same transitions after a current count require no new snapshot.
- Empty source publishes and caches zero as a valid result. One hundred repeated requests do not start additional work.
- A session with no layout manager returns one nil snapshot without spinning. Restoring the layout and requesting analysis recovers normally.

The test pauses the real link decorator after snapshot capture. It then changes subscription state on the main thread before allowing the worker to continue. The session methods and AppController observer methods are extracted from production without rewriting them. Fixture model, label, and view identity objects avoid opening a window or user library; NSTextStorage, NSLayoutManager, the notification center, worker queue, and word counter are real.

This evidence does not measure resident-memory peaks for word-heavy notes or certify native window visibility behavior. The known inability to interrupt an already-running individual count is outside this round's findings. Snapshot flags can cause a finite obsolete word calculation after the last client unsubscribes; the tested publication gate suppresses its result.
