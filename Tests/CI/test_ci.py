"""Exercise tag retries, publication guards, and macOS archive integrity."""

import importlib.util
import io
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import Mock
from urllib.error import HTTPError
import zipfile


def load_script(name):
    path = Path(__file__).resolve().parents[2] / ".github/scripts" / (name + ".py")
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


tagging = load_script("tag-build")
packaging = load_script("check-app-archive")


REPOSITORY = Path(__file__).resolve().parents[2]


def http_error(code):
    return HTTPError("https://api.github.com/test", code, "test response", {}, io.BytesIO())


class TagTests(unittest.TestCase):
    def setUp(self):
        self.environment = {
            "GITHUB_EVENT_NAME": "push",
            "GITHUB_REF": "refs/heads/master",
            "GITHUB_REPOSITORY": "example/nv",
            "GITHUB_SHA": "a" * 40,
            "GITHUB_RUN_NUMBER": "12",
            "GH_TOKEN": "test-token",
        }
        self.reference = {"object": {"type": "commit", "sha": "a" * 40}}

    def test_creates_tag_for_exact_built_commit(self):
        api = Mock(side_effect=[http_error(404), self.reference])
        self.assertEqual(tagging.tag_build(self.environment, api), "build-12")
        api.assert_called_with("POST", "/repos/example/nv/git/refs", "test-token",
                               {"ref": "refs/tags/build-12", "sha": "a" * 40})

    def test_rerun_reuses_tag_without_writing(self):
        api = Mock(return_value=self.reference)
        self.assertEqual(tagging.tag_build(self.environment, api), "build-12")
        api.assert_called_once_with("GET", "/repos/example/nv/git/ref/tags/build-12", "test-token")

    def test_never_moves_conflicting_or_annotated_tag(self):
        for target in [{"type": "commit", "sha": "b" * 40},
                       {"type": "tag", "sha": "a" * 40}]:
            with self.subTest(target=target):
                api = Mock(return_value={"object": target})
                with self.assertRaisesRegex(ValueError, "different target"):
                    tagging.tag_build(self.environment, api)
                self.assertEqual(api.call_count, 1)

    def test_concurrent_retry_accepts_only_same_commit(self):
        for commit in ["a" * 40, "b" * 40]:
            with self.subTest(commit=commit):
                api = Mock(side_effect=[http_error(404), http_error(422),
                                       {"object": {"type": "commit", "sha": commit}}])
                if commit == self.environment["GITHUB_SHA"]:
                    self.assertEqual(tagging.tag_build(self.environment, api), "build-12")
                else:
                    with self.assertRaises(ValueError):
                        tagging.tag_build(self.environment, api)

    def test_api_failure_is_not_treated_as_missing_tag(self):
        for code in [403, 429, 500]:
            with self.subTest(code=code):
                api = Mock(side_effect=http_error(code))
                with self.assertRaises(HTTPError):
                    tagging.tag_build(self.environment, api)
                self.assertEqual(api.call_count, 1)

    def test_unexplained_create_failure_remains_a_failure(self):
        api = Mock(side_effect=[http_error(404), http_error(422), http_error(404)])
        with self.assertRaises(HTTPError):
            tagging.tag_build(self.environment, api)

    def test_only_master_push_and_manual_events_can_tag(self):
        for event, ref in [("pull_request", "refs/heads/master"),
                           ("pull_request_target", "refs/heads/master"),
                           ("workflow_dispatch", "refs/heads/topic"),
                           ("push", "refs/tags/build-12")]:
            with self.subTest(event=event, ref=ref):
                api = Mock()
                environment = dict(self.environment, GITHUB_EVENT_NAME=event, GITHUB_REF=ref)
                with self.assertRaises(ValueError):
                    tagging.tag_build(environment, api)
                api.assert_not_called()
        environment = dict(self.environment, GITHUB_EVENT_NAME="workflow_dispatch")
        self.assertEqual(tagging.tag_build(environment, Mock(return_value=self.reference)), "build-12")

    def test_invalid_build_metadata_never_calls_api(self):
        for key, value in [("GITHUB_RUN_NUMBER", "0"), ("GITHUB_RUN_NUMBER", "12/3"),
                           ("GITHUB_SHA", "master"), ("GITHUB_REPOSITORY", "example"),
                           ("GH_TOKEN", "")]:
            with self.subTest(key=key, value=value):
                api = Mock()
                with self.assertRaises(ValueError):
                    tagging.tag_build(dict(self.environment, **{key: value}), api)
                api.assert_not_called()


class ArchiveTests(unittest.TestCase):
    syntax_resources = ("json.scm", "html.scm", "markdown.scm", "markdown-inline.scm", "ThirdPartyNotices.txt")

    def make_archive(self, path, executable=True, markdown_executable=True,
                     missing_syntax=None, invalid_syntax=None, syntax_body="fixture", syntax_mode=None,
                     missing_notice=None, notice_body="fixture", notice_mode=None):
        with zipfile.ZipFile(path, "w") as archive:
            def add(name, body, mode):
                info = zipfile.ZipInfo("nvALT.app/Contents/" + name)
                info.create_system = 3
                info.external_attr = mode << 16
                archive.writestr(info, body)

            add("Info.plist", "fixture", stat.S_IFREG | 0o644)
            add("MacOS/nvALT", "fixture", stat.S_IFREG | (0o755 if executable else 0o644))
            add("Resources/multimarkdown", "fixture", stat.S_IFREG | (0o755 if markdown_executable else 0o644))
            for name in self.syntax_resources:
                if name != missing_syntax:
                    body = syntax_body if name == invalid_syntax else "fixture"
                    mode = syntax_mode if name == invalid_syntax and syntax_mode is not None else stat.S_IFREG | 0o644
                    add("Resources/Syntax/" + name, body, mode)
            for name in ("FZF-GPL-3.0.txt", "FZF-MIT.txt", "UTF8PROC.txt"):
                if name != missing_notice:
                    add("Resources/SearchLicenses/" + name, notice_body, notice_mode or (stat.S_IFREG | 0o644))

    def test_search_notices_are_required_nonempty_regular_files(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "app.zip"
            for name in ("FZF-GPL-3.0.txt", "FZF-MIT.txt", "UTF8PROC.txt"):
                self.make_archive(path, missing_notice=name)
                with self.assertRaisesRegex(ValueError, "Missing search notice"):
                    packaging.check_archive(path)
            for kwargs in ({"notice_body": " \n"}, {"notice_mode": stat.S_IFLNK | 0o777}, {"notice_mode": stat.S_IFDIR | 0o755}):
                self.make_archive(path, **kwargs)
                with self.assertRaisesRegex(ValueError, "Search notice must be a nonempty regular file"):
                    packaging.check_archive(path)

    def test_archive_preserves_required_executables_and_syntax_resources(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "app.zip"
            self.make_archive(path)
            packaging.check_archive(path)

    def test_lost_executable_permissions_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "app.zip"
            self.make_archive(path, executable=False)
            with self.assertRaisesRegex(ValueError, "executable permissions"):
                packaging.check_archive(path)

    def test_lost_markdown_executable_permissions_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "app.zip"
            self.make_archive(path, markdown_executable=False)
            with self.assertRaisesRegex(ValueError, "executable permissions"):
                packaging.check_archive(path)

    def test_missing_syntax_resources_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "app.zip"
            for name in self.syntax_resources:
                with self.subTest(resource=name):
                    self.make_archive(path, missing_syntax=name)
                    with self.assertRaisesRegex(ValueError, "Missing syntax resource: Resources/Syntax/" + name):
                        packaging.check_archive(path)

    def test_empty_syntax_resources_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "app.zip"
            for name in self.syntax_resources:
                for body in ("", " \n\t"):
                    with self.subTest(resource=name, body=body):
                        self.make_archive(path, invalid_syntax=name, syntax_body=body)
                        with self.assertRaisesRegex(ValueError, "nonempty regular file: Resources/Syntax/" + name):
                            packaging.check_archive(path)

    def test_syntax_symlinks_and_directories_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "app.zip"
            for name in self.syntax_resources:
                for mode in (stat.S_IFLNK | 0o777, stat.S_IFDIR | 0o755):
                    with self.subTest(resource=name, mode=mode):
                        self.make_archive(path, invalid_syntax=name, syntax_mode=mode)
                        with self.assertRaisesRegex(ValueError, "nonempty regular file: Resources/Syntax/" + name):
                            packaging.check_archive(path)


class ProjectMetadataTests(unittest.TestCase):
    def test_removed_editor_artifacts_are_absent_from_build_metadata(self):
        project = (REPOSITORY / "Notation.xcodeproj/project.pbxproj").read_text()
        self.assertNotIn("IBeamInverted.png", project)

        removed_methods = (
            "-[LinkingEditor isContinuousSpellCheckingEnabled]",
            "-[LinkingEditor readablePasteboardTypes]",
            "-[LinkingEditor acceptableDragTypes]",
        )
        for filename in ("Notation.freqorder", "Notation.launchorder"):
            order = (REPOSITORY / "Config" / filename).read_text()
            for method in removed_methods:
                with self.subTest(order_file=filename, method=method):
                    self.assertNotIn(method, order)


if __name__ == "__main__":
    unittest.main()
