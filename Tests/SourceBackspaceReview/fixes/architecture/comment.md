Resolved the round 3 Ousterhout P3 documentation finding in `architecture.md`.

The note-switch description now separates cancellation from attribute removal. Explicit cleanup cancels the old scheduled selector. If character editing remains open, removal stays deferred and drawing suppresses stale backgrounds. Otherwise, removal completes before the layout manager changes storage.

All nine static source/doc consistency checks pass. The four production source hashes remain unchanged. This correction adds no runtime validation.

Evidence: `Tests/SourceBackspaceReview/fixes/architecture/{check.py,output.json,manifest.json}`.
