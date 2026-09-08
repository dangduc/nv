#!/usr/bin/env python3
"""Final PR artifact/retained-dependency experiment, with disposable mutations."""
import hashlib
import json
from pathlib import Path
import plistlib
import stat
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
APP = ROOT / "build/DerivedData/Build/Products/Development/nvALT.app"
OBJECTS = ROOT / "build/DerivedData/Build/Intermediates.noindex/Notation.build/Development/Notation.build/Objects-normal/x86_64"
checks = 0


def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], cwd=ROOT, capture_output=True, text=True, timeout=60, **kwargs)


def output(*args):
    result = run(*args)
    if result.returncode:
        raise AssertionError(f"command failed: {args}\n{result.stderr}")
    return result.stdout


def check(condition, description):
    global checks
    if not condition:
        raise AssertionError(description)
    checks += 1
    print("PASS:", description, flush=True)


def fingerprint(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


print("reviewed head:", output("git", "rev-parse", "HEAD").strip(), flush=True)
print("app executable SHA-256:", fingerprint(APP / "Contents/MacOS/nvALT"), flush=True)
check(run("git", "diff", "--exit-code", "f38a8cb", "HEAD", "--", "Sources", "Resources", "ThirdParty", "Config", "Notation.xcodeproj", ".github/workflows").returncode == 0, "final production/build tree matches the reviewed app implementation")
tracked = output("git", "ls-files").splitlines()
check(not any(p.startswith("Sources/Sync/") or p.endswith("SimperiumConfig-example.h") for p in tracked), "tracked source has no sync implementation or API-key example")
project = output("plutil", "-convert", "json", "-o", "-", "Notation.xcodeproj/project.pbxproj")
check("SimperiumConfig" not in project and "Sources/Sync" not in project, "target configuration does not refer to removed service configuration")
# This final round checks the exact link invocation inputs; round 1 checked project resources/nibs.
link_inputs = (OBJECTS / "nvALT.LinkFileList").read_text().splitlines()
check(all(Path(p).is_file() for p in link_inputs), f"all {len(link_inputs)} final linker object inputs exist")
check(not any(any(token in p for token in ("Simplenote", "SyncSession", "SyncResponse", "NotationSync")) for p in link_inputs), "final link inputs contain no retired service objects")
check(set(p.split("/")[1] for p in tracked if p.startswith("ThirdParty/")) == {"Crypto", "MultiMarkdown", "ODBEditor", "OpenSSL", "PTHotKeys", "Textile_2.12", "TreeSitter"}, "seven retained vendored boundaries enumerated")

with tempfile.TemporaryDirectory(prefix="simplenote-r3-artifact-", dir=ROOT / "build") as temporary:
    work = Path(temporary)
    archive = work / "nvALT-ci.zip"
    output("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", APP, archive)
    ci = output("python3", ".github/scripts/check-app-archive.py", archive)
    print(ci.strip(), flush=True)
    check("App archive checks passed." in ci, "CI archive checker accepts final built app")
    with zipfile.ZipFile(archive) as zipped:
        check(zipped.testzip() is None, "independent ZIP CRC check passes")
        entries = {i.filename: i for i in zipped.infolist() if i.filename.startswith("nvALT.app/") and not i.is_dir()}
        files = {"nvALT.app/" + p.relative_to(APP).as_posix(): p for p in APP.rglob("*") if p.is_file()}
        check(entries.keys() == files.keys(), f"ZIP contains exactly all {len(files)} built app files")
        check(all(zipped.read(name) == source.read_bytes() for name, source in files.items()), "every archived app file is byte-identical to the built file")
        check(all(stat.S_IMODE(entries[name].external_attr >> 16) == stat.S_IMODE(source.stat().st_mode) for name, source in files.items()), "every archived file retains its permission bits")
        check(not any(any(token.lower() in name.lower() for token in ("Simplenote", "SimperiumConfig", "Sparkle.framework", "SyncSession")) for name in entries), "archive names exclude retired sync/configuration/framework assets")
    output("ditto", "-x", "-k", archive, work / "extracted")
    extracted = work / "extracted/nvALT.app"
    resources = extracted / "Contents/Resources"
    binary = extracted / "Contents/MacOS/nvALT"
    check(fingerprint(binary) == fingerprint(APP / "Contents/MacOS/nvALT"), "extracted executable matches reviewed executable")
    check(output("lipo", "-archs", binary).strip() == "x86_64", "extracted app has the required Intel architecture")
    dylibs = [line.strip().split(" (", 1)[0] for line in output("otool", "-L", binary).splitlines()[1:]]
    check(all(p.startswith(("/System/Library/", "/usr/lib/")) for p in dylibs), f"all {len(dylibs)} direct dynamic dependencies use system paths")
    check(not any("SystemConfiguration.framework" in p or "IOKit.framework" in p or "Sparkle" in p for p in dylibs), "retired direct frameworks are absent from shipped load commands")
    check(not any(p.suffix == ".framework" for p in extracted.rglob("*")), "app contains no embedded vendor framework")
    info = plistlib.loads((extracted / "Contents/Info.plist").read_bytes())
    check(not any("simplenote" in str(x).lower() or "simperium" in str(x).lower() for x in info.values()), "shipped Info.plist has no Simplenote or Simperium registration")
    symbols = output("nm", "-j", binary)
    for old in ("SimplenoteSession", "SimplenoteEntryCollector", "SyncResponseFetcher", "SyncSessionController"):
        check("_OBJC_CLASS_$_" + old not in symbols, "shipped binary excludes retired class " + old)

    consumers = {
        "Crypto": ("NSData_transformations.o", ["_pbkdf2_sha1", "_BrokenMD5Final", "_sha1_finish_ctx"]),
        "OpenSSL": ("NSData_transformations.o", ["_EVP_aes_256_cbc", "_EVP_EncryptUpdate", "_EVP_DecryptUpdate"]),
        "PTHotKeys": ("GlobalPrefs.o", ["_OBJC_CLASS_$_PTHotKey", "_OBJC_CLASS_$_PTHotKeyCenter", "_OBJC_CLASS_$_PTKeyCombo"]),
        "ODBEditor": ("NotationController.o", ["_OBJC_CLASS_$_ODBEditor"]),
        "TreeSitter": ("NVSourceHighlighter.o", ["_ts_parser_new", "_ts_query_new", "_tree_sitter_json", "_tree_sitter_html", "_tree_sitter_markdown", "_tree_sitter_markdown_inline"]),
    }
    for dependency, (consumer, required) in consumers.items():
        undefined = output("nm", "-u", OBJECTS / consumer).splitlines()
        check(str(OBJECTS / consumer) in link_inputs, dependency + " consumer belongs to the final link")
        check(all(symbol in undefined for symbol in required), dependency + " has real references from retained local consumer " + consumer)
        defined = output("nm", "-U", "-j", binary).splitlines()
        check(all(symbol in defined for symbol in required), dependency + " required definitions exist in shipped executable")
    blor = output("nm", "-u", OBJECTS / "BlorPasswordRetriever.o").splitlines()
    check("_idea_cfb64_encrypt" in blor and "_idea_set_encrypt_key" in blor, "legacy local password import still references vendored IDEA")
    check("_hmac_sha1" in output("nm", "-u", OBJECTS / "pbkdf2.o").splitlines(), "retained local PBKDF2 consumes vendored HMAC-SHA1")

    check((resources / "multimarkdown").read_bytes() == (ROOT / "ThirdParty/MultiMarkdown/multimarkdown").read_bytes(), "packaged MultiMarkdown is the tracked helper")
    markdown = output(resources / "multimarkdown", "--version")
    print("MultiMarkdown version:", markdown.strip(), flush=True)
    conversion = run(resources / "multimarkdown", input="# Artifact review\n\n**bold** & <test>\n")
    check(conversion.returncode == 0 and "<strong>bold</strong>" in conversion.stdout and ">Artifact review</h1>" in conversion.stdout, "extracted MultiMarkdown executes local heading/bold conversion")
    textile_files = [p for p in (ROOT / "ThirdParty/Textile_2.12").rglob("*") if p.is_file()]
    check(all((resources / "Textile_2.12" / p.relative_to(ROOT / "ThirdParty/Textile_2.12")).read_bytes() == p.read_bytes() for p in textile_files), "every packaged Textile file matches tracked helper/module bytes")
    conversion = run("/usr/bin/perl", resources / "Textile_2.12/textilize.pl", input="h1. Artifact review\n\n*bold*\n")
    check(conversion.returncode == 0 and "<strong>bold</strong>" in conversion.stdout and "<h1>Artifact review</h1>" in conversion.stdout, "extracted Textile helper executes local heading/bold conversion")
    query_manifest = json.loads((ROOT / "ThirdParty/TreeSitter/manifest.json").read_text())["queries"]
    check(all(fingerprint(extracted / "Contents" / path) == metadata["sha256"] for path, metadata in query_manifest.items()), "all four extracted highlighting queries match pinned manifest hashes")
    check((resources / "Syntax/ThirdPartyNotices.txt").read_bytes() == (ROOT / "Resources/Syntax/ThirdPartyNotices.txt").read_bytes(), "extracted syntax licenses match tracked notices")
    key_codes = json.loads(output("plutil", "-convert", "json", "-o", "-", resources / "PTKeyCodes.plist"))
    source_codes = json.loads(output("plutil", "-convert", "json", "-o", "-", ROOT / "ThirdParty/PTHotKeys/PTKeyCodes.plist"))
    check(bool(key_codes) and key_codes == source_codes, "packaged hotkey names remain readable and match tracked mapping")
    tree_objects = sorted(OBJECTS.glob("NVTreeSitter*.o"))
    check(len(tree_objects) == 8 and all(str(p) in link_inputs for p in tree_objects), "native experiment reuses all eight parser objects from final app link")
    native = work / "dependencies"
    compile_result = run("xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13", "-IThirdParty/TreeSitter/runtime/include", "-IThirdParty/OpenSSL/include", "-IThirdParty/Crypto", HERE / "dependencies.c", *tree_objects, OBJECTS / "pbkdf2.o", OBJECTS / "hmacsha1.o", "ThirdParty/OpenSSL/lib/libcrypto.a", "-o", native)
    check(compile_result.returncode == 0, "review executable links existing parser/Crypto objects and retained OpenSSL archive: " + compile_result.stderr.strip())
    result = run(native, resources)
    (HERE / "native.log").write_text(result.stdout + result.stderr)
    check(result.returncode == 0, "native parser/query/crypto experiment passes")
    print(result.stdout, end="", flush=True)

    # Mutations stay in the extracted disposable bundle. Each invalidates a real local operation.
    module = resources / "Textile_2.12/Text/Textile.pm"
    saved = module.read_bytes(); module.unlink()
    failure = run("/usr/bin/perl", resources / "Textile_2.12/textilize.pl", input="h1. Artifact review\n")
    (HERE / "missing-textile.log").write_text(failure.stdout + failure.stderr)
    check(failure.returncode != 0 and "Can't locate Text/Textile.pm" in failure.stderr, "negative control: missing retained Textile module prevents conversion")
    module.write_bytes(saved)
    query = resources / "Syntax/json.scm"
    saved = query.read_bytes(); query.unlink()
    failure = run(native, resources)
    (HERE / "missing-query.log").write_text(failure.stdout + failure.stderr)
    check(failure.returncode != 0 and "FAIL: shipped syntax query opens" in failure.stderr, "negative control: missing shipped query is rejected by native experiment")
    query.write_bytes(saved)
    helper = resources / "multimarkdown"
    helper.chmod(helper.stat().st_mode & ~0o111)
    try:
        run(helper, input="# Title\n")
    except PermissionError:
        check(True, "negative control: lost MultiMarkdown execute bits prevent conversion")
    else:
        check(False, "lost MultiMarkdown execute bits must prevent conversion")
print(f"PASS: {checks} artifact assertions plus native dependency assertions", flush=True)
