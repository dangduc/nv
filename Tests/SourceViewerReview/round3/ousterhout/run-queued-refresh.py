#!/usr/bin/env python3
"""Check workflow preparation against a queued refresh during native inspection."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[4]
body = (repo / "Tests/Regression/source-workflow/probe-body.m").read_text()
changes = {
    "NSString *(^prepareControlledDocument)(void)":
        "__block NSUInteger preparationRetries = 0;\n            NSString *(^prepareControlledDocument)(void)",
    "for (NSUInteger attempt = 0; attempt < 4; attempt++) {":
        "for (NSUInteger attempt = 0; attempt < 4; attempt++) {\n                    if (attempt == 0) [a performSelector:@selector(updateViewerSnapshot) withObject:nil afterDelay:0];\n                    else preparationRetries++;",
    "// Authoritative saved-window restoration must invalidate pending":
        'Check(preparationRetries >= 6, @"all six histories retry after a deliberately queued refresh during native inspection");\n            // Authoritative saved-window restoration must invalidate pending',
}
for before, after in changes.items():
    assert body.count(before) == 1
    body = body.replace(before, after)
with tempfile.TemporaryDirectory(prefix="nv-round3-queued-refresh-") as root:
    path = Path(root) / "workflow.m"
    path.write_text(body)
    result = subprocess.run([sys.executable, str(Path(__file__).with_name("run-browser.py"))],
        env=dict(os.environ, NV_REVIEW_BODY_PATH=str(path)), timeout=180)
    raise SystemExit(result.returncode)
