"""Reject application identities that mix release and Development registrations."""

import copy
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / ".github/scripts/check-app-identity.py"
SPEC = importlib.util.spec_from_file_location("app_identity", SCRIPT)
identity = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(identity)


def fixture(flavor):
    development = flavor == "development"
    name = "nvALT Development" if development else "nvALT"
    identifier = "net.elasticthreads.nv.development" if development else "net.elasticthreads.nv"
    return {
        "CFBundleName": name,
        "CFBundleDisplayName": name,
        "CFBundleExecutable": name,
        "CFBundleIdentifier": identifier,
        "CFBundleSignature": "NvDv" if development else "N†l√",
        "NVBuildFlavor": flavor,
        "CFBundleURLTypes": [{
            "CFBundleURLName": identifier,
            "CFBundleURLSchemes": ["nvalt-dev", "nv-dev"] if development else ["nvalt", "nv"],
        }],
        "CFBundleDocumentTypes": [{"LSHandlerRank": "None" if development else "Default"}] * 2,
        "NSServices": [{
            "NSMenuItem": {"default": name + ": New Note from Selection"},
            "NSPortName": name,
            "NSKeyEquivalent": {"default": "" if development else "V"},
        }],
    }


class IdentityTests(unittest.TestCase):
    def test_release_and_development_identities_are_valid(self):
        for flavor in ("release", "development"):
            with self.subTest(flavor=flavor):
                identity.check_identity(fixture(flavor), flavor)

    def test_development_rejects_release_identity_fields(self):
        release = fixture("release")
        for key in ("CFBundleName", "CFBundleDisplayName", "CFBundleExecutable",
                    "CFBundleIdentifier", "CFBundleSignature", "NVBuildFlavor"):
            with self.subTest(key=key):
                info = fixture("development")
                info[key] = release[key]
                with self.assertRaisesRegex(ValueError, key):
                    identity.check_identity(info, "development")

    def test_development_cannot_register_either_release_url_scheme(self):
        for scheme in ("nv", "nvalt"):
            with self.subTest(scheme=scheme):
                info = fixture("development")
                info["CFBundleURLTypes"][0]["CFBundleURLSchemes"].append(scheme)
                with self.assertRaisesRegex(ValueError, "URL registrations"):
                    identity.check_identity(info, "development")

    def test_development_cannot_claim_default_document_handling(self):
        info = fixture("development")
        info["CFBundleDocumentTypes"][0]["LSHandlerRank"] = "Default"
        with self.assertRaisesRegex(ValueError, "document handler rank"):
            identity.check_identity(info, "development")

    def test_development_rejects_each_release_service_field(self):
        release_service = fixture("release")["NSServices"][0]
        for key, value in release_service.items():
            with self.subTest(key=key):
                info = fixture("development")
                info["NSServices"][0][key] = copy.deepcopy(value)
                with self.assertRaisesRegex(ValueError, "selection service identity"):
                    identity.check_identity(info, "development")

    def make_app(self, root, flavor):
        info = fixture(flavor)
        app = root / (info["CFBundleName"] + ".app")
        executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
        executable.parent.mkdir(parents=True)
        executable.write_text("fixture")
        executable.chmod(0o755)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        return app, executable

    def test_built_app_requires_correct_filename_and_executable(self):
        with tempfile.TemporaryDirectory() as directory:
            for flavor in ("release", "development"):
                with self.subTest(flavor=flavor):
                    app, executable = self.make_app(Path(directory), flavor)
                    identity.check_app(app, flavor)
                    executable.chmod(0o644)
                    with self.assertRaisesRegex(ValueError, "Missing executable"):
                        identity.check_app(app, flavor)
                    renamed = app.with_name("Wrong " + app.name)
                    app.rename(renamed)
                    with self.assertRaisesRegex(ValueError, "application filename"):
                        identity.check_app(renamed, flavor)

    def test_localization_cannot_hide_development_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            app, _ = self.make_app(Path(directory), "development")
            strings = app / "Contents/Resources/en.lproj/InfoPlist.strings"
            strings.parent.mkdir(parents=True)
            strings.write_bytes(plistlib.dumps({"CFBundleName": "nvALT"}))
            with self.assertRaisesRegex(ValueError, "localized development CFBundleName"):
                identity.check_app(app, "development")


if __name__ == "__main__":
    unittest.main()
