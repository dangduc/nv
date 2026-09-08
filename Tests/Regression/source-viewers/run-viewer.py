#!/usr/bin/env python3
"""Run the standalone WK viewer in an isolated app with disposable assets."""
from pathlib import Path
import base64
import fcntl
import http.server
import threading
import os
import plistlib
import shutil
import subprocess
import tempfile
import uuid

repo = Path(__file__).resolve().parents[3]
lock_path = repo / "build/pr-review/gui.lock"
lock_path.parent.mkdir(parents=True, exist_ok=True)
with lock_path.open("w") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    with tempfile.TemporaryDirectory(prefix="nvalt-inline-viewer-") as temporary:
        root = Path(temporary)
        app = root / "Viewer Tests.app"
        resources = app / "Contents/Resources"
        resources.mkdir(parents=True)
        binary = app / "Contents/MacOS/ViewerTests"
        binary.parent.mkdir()
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "org.nvalt.viewer-tests." + uuid.uuid4().hex,
            "CFBundleExecutable": "ViewerTests", "CFBundlePackageType": "APPL",
            "NSPrincipalClass": "NSApplication", "NSHighResolutionCapable": True,
        }))
        shutil.copy2(repo / "ThirdParty/MultiMarkdown/multimarkdown", resources / "multimarkdown")
        shutil.copytree(repo / "ThirdParty/Textile_2.12", resources / "Textile_2.12")
        assets = root / "Assets"
        assets.mkdir()
        pixel = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aL1sAAAAASUVORK5CYII=")
        (assets / "pixel.png").write_bytes(pixel)
        (root / "outside.png").write_bytes(pixel)
        sdk = Path(subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip())
        subprocess.run([
            "xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13", "-fno-objc-arc", "-fblocks",
            "-Wno-deprecated-declarations", "-framework", "Cocoa", "-framework", "WebKit", "-lxml2",
            "-I", str(sdk / "usr/include/libxml2"), "-I", str(repo / "Sources/Preview"),
            str(repo / "Sources/Preview/NVNoteContentSnapshot.m"), str(repo / "Sources/Preview/NVMarkupRenderer.m"),
            str(repo / "Sources/Preview/PreviewController.m"), str(Path(__file__).with_name("viewer-tests.m")),
            "-o", str(binary),
        ], check=True)
        requests = []
        class AssetServer(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append(self.path)
                self.send_response(200)
                self.send_header("Content-Type", "image/png")
                self.end_headers()
                self.wfile.write(pixel)

            def log_message(self, *args):
                pass

        server = http.server.HTTPServer(("127.0.0.1", 0), AssetServer)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            subprocess.run([str(binary)], env=dict(os.environ, NV_VIEWER_ASSET_ROOT=str(assets),
                NV_VIEWER_REMOTE_URL=f"http://127.0.0.1:{server.server_port}/blocked.png"), check=True, timeout=90)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
        assert not requests, f"The viewer contacted the remote resource fixture: {requests}"
        print("PASS: remote resource policy made no requests to the listening fixture server")
