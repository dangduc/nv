#!/usr/bin/env python3
"""Exercise real development/release app copies in one disposable user home."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

repo = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags


def bundle_info(app):
    return plistlib.loads((app / "Contents/Info.plist").read_bytes())


def check_metadata(app, flavor):
    info = bundle_info(app)
    expected = {
        "development": ("nvALT Development", "net.elasticthreads.nv.development", "nvalt-dev"),
        "release": ("nvALT", "net.elasticthreads.nv", "nvalt"),
    }[flavor]
    assert info["CFBundleExecutable"] == expected[0], info
    assert info["CFBundleIdentifier"] == expected[1], info
    assert info["NVBuildFlavor"] == flavor, info
    assert app.name == expected[0] + ".app", app
    schemes = {scheme for item in info.get("CFBundleURLTypes", []) for scheme in item.get("CFBundleURLSchemes", [])}
    assert expected[2] in schemes, schemes
    if flavor == "development":
        assert "nvalt" not in schemes and "nv" not in schemes, schemes
    assert (app / "Contents/MacOS" / expected[0]).is_file()
    print(f"PASS: {flavor} built bundle metadata", flush=True)
    return info


def run_pair(apps, root, dylib, output, phase):
    processes = {}
    streams = []
    try:
        for flavor, app in apps.items():
            info = bundle_info(app)
            environment = dict(os.environ, NV_ISOLATION_ROOT=str(root), NV_ISOLATION_FLAVOR=flavor,
                NV_ISOLATION_PHASE=phase, NV_ISOLATION_SCREENSHOTS=str(output / "screenshots"), DYLD_INSERT_LIBRARIES=str(dylib),
                CFFIXED_USER_HOME=str(root / "Home"), TMPDIR=str(root / "Temp") + "/")
            stream = (output / f"{flavor}-{phase}.log").open("w")
            streams.append(stream)
            processes[flavor] = subprocess.Popen([str(app / "Contents/MacOS" / info["CFBundleExecutable"]),
                "-ShowDockIcon", "YES", "-StatusBarItem", "NO", "-QuitWhenClosingMainWindow", "NO",
                "-SUEnableAutomaticChecks", "NO", "-SUAutomaticallyUpdate", "NO"],
                env=environment, stdout=stream, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 70
        reports = {}
        while len(reports) < 2:
            for flavor, process in processes.items():
                if process.poll() is not None:
                    raise RuntimeError(f"{flavor} {phase} exited before barrier ({process.returncode}); see {output / (flavor + '-' + phase + '.log')}")
                ready = root / f"{flavor}-{phase}.ready.plist"
                if ready.exists():
                    reports[flavor] = plistlib.loads(ready.read_bytes())
            if time.monotonic() > deadline:
                raise TimeoutError(f"{phase} apps did not reach the concurrent barrier; see {output}")
            time.sleep(0.05)
        assert all(process.poll() is None for process in processes.values())
        assert len({report["pid"] for report in reports.values()}) == 2
        for key in ("notes", "support", "cache", "backup", "editing", "keychainService", "bundleIdentifier"):
            assert reports["development"][key] != reports["release"][key], (phase, key, reports)
        (root / f"{phase}.continue").touch()
        for flavor, process in processes.items():
            code = process.wait(timeout=30)
            assert code == 0, (flavor, phase, code)
            passed = root / f"{flavor}-{phase}.passed.plist"
            assert passed.is_file(), (flavor, phase)
            reports[flavor] = plistlib.loads(passed.read_bytes())
        print(f"PASS: {phase}: both apps ran together with separate notes, preferences, backups, caches, and edit directories", flush=True)
        return reports
    finally:
        for process in processes.values():
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        for stream in streams:
            stream.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    products = repo / "build/DerivedData/Build/Products"
    parser.add_argument("--development-app", type=Path, default=products / "Development/nvALT Development.app")
    parser.add_argument("--release-app", type=Path, default=products / "ForBuilding/nvALT.app")
    parser.add_argument("--output", type=Path, default=repo / "build/pr-review/development-isolation")
    args = parser.parse_args()
    sources = {"development": args.development_app.resolve(), "release": args.release_app.resolve()}
    metadata = {flavor: check_metadata(app, flavor) for flavor, app in sources.items()}
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    (output / "screenshots").mkdir(exist_ok=True)
    # All worktrees share this exact lock, including the root repository suites.
    common_git = Path(subprocess.check_output(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], cwd=repo, text=True).strip())
    lock_path = common_git.parent / "build/pr-review/gui.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    domains = []
    with lock_path.open("a") as lock, tempfile.TemporaryDirectory(prefix="nvalt-build-isolation-", dir=repo / "build") as temporary:
        print(f"Waiting for GUI lock: {lock_path}", flush=True)
        fcntl.flock(lock, fcntl.LOCK_EX)
        root = Path(temporary).resolve()
        for folder in ("Home/Library/Application Support", "Home/Library/Caches", "Home/Library/Preferences",
                       "Home/Documents", "Home/Desktop", "Home/.Trash", "Temp"):
            (root / folder).mkdir(parents=True, exist_ok=True)
        apps = {}
        try:
            for flavor, source in sources.items():
                app = root / flavor / source.name
                shutil.copytree(source, app, symlinks=True)
                info = dict(metadata[flavor])
                domain = "org.nvalt.development-isolation." + flavor + "." + uuid.uuid4().hex
                domains.append(domain)
                info["CFBundleIdentifier"] = domain
                (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
                apps[flavor] = app
            dylib = root / "IsolationProbe.dylib"
            subprocess.run(["xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13", "-dynamiclib",
                "-undefined", "dynamic_lookup", "-fno-objc-arc", "-Wno-deprecated-declarations",
                *include_flags(repo), "-include", str(repo / "Config/Notation_Prefix.pch"),
                "-framework", "Cocoa", "-framework", "Carbon", "-framework", "Security",
                "-o", str(dylib), str(repo / "Tests/DevelopmentBuild/IsolationProbe.m")], check=True)
            first = run_pair(apps, root, dylib, output, "first")
            relaunch = run_pair(apps, root, dylib, output, "relaunch")
            for flavor in sources:
                for key in ("notes", "support", "cache", "backup", "editing", "bundleIdentifier"):
                    assert first[flavor][key] == relaunch[flavor][key], (flavor, key)
            (output / "results.json").write_text(json.dumps({"first": first, "relaunch": relaunch}, indent=2) + "\n")
            print(f"PASS: relaunch retained each build's notes, font, editor color, and backup settings. Reports: {output}")
        finally:
            # Domains are generated for this run only. Neither production domain is touched.
            for domain in domains:
                subprocess.run(["defaults", "delete", domain], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    main()
