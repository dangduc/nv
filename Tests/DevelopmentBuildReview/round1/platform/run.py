#!/usr/bin/env python3
"""Disposable scheme, CI shell, and release package checks. No app launch."""

from concurrent.futures import ThreadPoolExecutor
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import textwrap
import xml.etree.ElementTree as ET
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
PRODUCTS = ROOT / "build/DerivedData/Build/Products"
WORKFLOW = (ROOT / ".github/workflows/macos.yml").read_text()
RESULTS = {}


def run(command, cwd=ROOT, env=None, check=True, timeout=45):
    completed = subprocess.run(command, cwd=cwd, env=env, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               timeout=timeout)
    if check and completed.returncode:
        raise AssertionError((command, completed.returncode, completed.stdout))
    return completed


def workflow_script(name):
    step = WORKFLOW.split("      - name: " + name + "\n", 1)[1].split("      - name:", 1)[0]
    return textwrap.dedent(step.split("        run: |\n", 1)[1]).rstrip() + "\n"


def load_checker():
    spec = importlib.util.spec_from_file_location("identity", ROOT / ".github/scripts/check-app-identity.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def scheme_probe(temp):
    expected = {"Notation Release": ("ForBuilding", "nvALT", "release"),
                "Notation Develop": ("Development", "nvALT Development", "development")}
    def one(item):
        scheme, action = item
        configuration, name, flavor = expected[scheme]
        command = ["xcodebuild", "-project", "Notation.xcodeproj", "-scheme", scheme,
                   "-derivedDataPath", str(temp / (flavor + "-" + action)),
                   "ARCHS=x86_64", "MACOSX_DEPLOYMENT_TARGET=10.13", "CODE_SIGNING_ALLOWED=NO",
                   "GENERATE_PROFILING_CODE=NO", "OTHER_CFLAGS=", "WARNING_LDFLAGS=",
                   "-showBuildSettings", "-json", action]
        raw = run(command).stdout
        # Xcode sends destination warnings to stderr before the JSON document.
        document, _ = json.JSONDecoder().raw_decode(raw[raw.index("[\n"):])
        settings = next(entry["buildSettings"] for entry in document
                        if entry["target"] == "Notation")
        keys = ["CONFIGURATION", "PRODUCT_NAME", "EXECUTABLE_NAME", "FULL_PRODUCT_NAME",
                "PRODUCT_BUNDLE_IDENTIFIER", "NV_BUILD_FLAVOR", "NV_URL_SCHEME",
                "MACOSX_DEPLOYMENT_TARGET", "TARGET_BUILD_DIR", "INSTALL_PATH"]
        result = {key: settings.get(key) for key in keys}
        assert result["CONFIGURATION"] == configuration, result
        assert result["PRODUCT_NAME"] == result["EXECUTABLE_NAME"] == name, result
        assert result["FULL_PRODUCT_NAME"] == name + ".app", result
        assert result["NV_BUILD_FLAVOR"] == flavor, result
        assert result["PRODUCT_BUNDLE_IDENTIFIER"] == "net.elasticthreads.nv" + (
            ".development" if flavor == "development" else ""), result
        assert result["MACOSX_DEPLOYMENT_TARGET"] == "10.13", result
        return scheme + ":" + action, result
    with ThreadPoolExecutor(max_workers=4) as executor:
        results = dict(executor.map(one, [(scheme, action) for scheme in expected
                                         for action in ("build", "archive")]))
    for scheme, (configuration, name, flavor) in expected.items():
        document = ET.parse(ROOT / "Notation.xcodeproj/xcshareddata/xcschemes" / (scheme + ".xcscheme"))
        for action in ("TestAction", "LaunchAction", "ProfileAction", "AnalyzeAction", "ArchiveAction"):
            assert document.find(action).get("buildConfiguration") == configuration
        for reference in document.findall(".//BuildableReference"):
            assert reference.get("BuildableName") == name + ".app"
    RESULTS["scheme_actions"] = results


def pipeline_probe(temp):
    fake_bin = temp / "bin"
    fake_bin.mkdir()
    fake = fake_bin / "xcodebuild"
    fake.write_text("#!/usr/bin/env python3\nimport os, sys\n"
                    "if '-version' in sys.argv: print('fixture Xcode'); sys.exit(0)\n"
                    "scheme = sys.argv[sys.argv.index('-scheme') + 1]\n"
                    "with open(os.environ['PROBE_CALLS'], 'a') as stream: stream.write(scheme + '\\n')\n"
                    "print(scheme)\nsys.exit(71 if scheme == os.environ['PROBE_FAIL_SCHEME'] else 0)\n")
    fake.chmod(0o755)
    script = workflow_script("Build both configurations without signing")
    results = []
    for fail in ("Notation Release", "Notation Develop", "none"):
        case = temp / fail.replace(" ", "-")
        case.mkdir()
        calls = case / "calls.txt"
        env = dict(os.environ, PATH=str(fake_bin) + os.pathsep + os.environ["PATH"],
                   PROBE_CALLS=str(calls), PROBE_FAIL_SCHEME=fail)
        completed = run(["/bin/bash", "-c", script], cwd=case, env=env, check=False)
        seen = calls.read_text().splitlines()
        expected_seen = ["Notation Release"] if fail == "Notation Release" else ["Notation Release", "Notation Develop"]
        assert seen == expected_seen, (fail, seen)
        assert completed.returncode == (0 if fail == "none" else 71), (fail, completed.stdout)
        results.append({"failure": fail, "exit": completed.returncode, "build_calls": seen})
    RESULTS["pipeline_failure_controls"] = results


def package_probe(temp):
    checkout = temp / "package-checkout"
    target = checkout / "build/DerivedData/Build/Products"
    target.parent.mkdir(parents=True)
    target.symlink_to(PRODUCTS, target_is_directory=True)
    (checkout / ".github").symlink_to(ROOT / ".github", target_is_directory=True)
    env = dict(os.environ, GITHUB_RUN_NUMBER="1", GITHUB_RUN_ATTEMPT="1",
               GITHUB_OUTPUT=str(temp / "github-output"))
    completed = run(["/bin/bash", "-c", workflow_script("Package the app")], cwd=checkout, env=env)
    archive = checkout / "build/nvALT-macos-x86_64-1-1.zip"
    extracted = temp / "extracted"
    run(["ditto", "-x", "-k", str(archive), str(extracted)])
    app = extracted / "nvALT.app"
    checker = load_checker()
    checker.check_app(app, "release")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    original_info = plistlib.loads((PRODUCTS / "ForBuilding/nvALT.app/Contents/Info.plist").read_bytes())
    assert info == original_info
    binary = app / "Contents/MacOS/nvALT"
    macho = run(["otool", "-l", str(binary)]).stdout
    min_os = re.search(r"cmd LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version ([\d.]+)", macho)
    if not min_os:
        min_os = re.search(r"cmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform \S+\s+minos ([\d.]+)", macho)
    assert min_os and min_os.group(1) == info["LSMinimumSystemVersion"] == "10.13", macho
    assert info["LSMinimumSystemVersionByArchitecture"]["x86_64"] == "10.13"
    baseline = plistlib.loads(run(["git", "show", "bd74bf3:Config/Info.plist"]).stdout.encode())
    for key in ("CFBundleVersion", "CFBundleShortVersionString", "OSAScriptingDefinition"):
        assert info[key] == baseline[key], key
    mutant = dict(info, NVBuildFlavor="development")
    try:
        checker.check_identity(mutant, "release")
    except ValueError as error:
        rejected = str(error)
    else:
        raise AssertionError("A mismatched runtime flavor passed the release gate")
    with zipfile.ZipFile(archive) as stream:
        app_roots = sorted({Path(name).parts[0] for name in stream.namelist()
                            if Path(name).parts[0].endswith(".app")})
        assert app_roots == ["nvALT.app"], app_roots
    RESULTS["release_package"] = {"workflow_output": completed.stdout.strip(),
                                  "archive_bytes": archive.stat().st_size,
                                  "app_roots": app_roots, "identity": info["CFBundleIdentifier"],
                                  "flavor": info["NVBuildFlavor"], "minimum_os": min_os.group(1),
                                  "baseline_versions_retained": True,
                                  "mismatched_flavor_rejected": rejected}


if __name__ == "__main__":
    assert run(["git", "rev-parse", "--short", "HEAD"]).stdout.strip() == "2dbfd46"
    with tempfile.TemporaryDirectory(prefix="nvalt-platform-review-") as temporary:
        temp = Path(temporary)
        scheme_probe(temp)
        pipeline_probe(temp)
        package_probe(temp)
    (HERE / "results.json").write_text(json.dumps(RESULTS, indent=2) + "\n")
    print(json.dumps(RESULTS, indent=2))
    print("PASS: three hypotheses, four scheme/action pairs, three pipeline cases, one package, one metadata negative control")
