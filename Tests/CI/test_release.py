"""Exercise release boundaries and failure handling without remote writes."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock

from test_ci import load_script


publishing = load_script("publish-release")


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.archive = Path(self.directory.name) / "nvALT-macos-x86_64-12-1.zip"
        self.archive.write_bytes(b"archive fixture")
        self.environment = {
            "GITHUB_EVENT_NAME": "push",
            "GITHUB_REF": "refs/heads/2026.09-release",
            "GITHUB_REPOSITORY": "example/nv",
            "GITHUB_SHA": "a" * 40,
            "GITHUB_RUN_NUMBER": "12",
            "GITHUB_RUN_ATTEMPT": "1",
            "GITHUB_RUN_ID": "1234",
            "GH_TOKEN": "test-token",
        }

    def reference(self, commit="a" * 40, kind="commit", tag="release-12-1"):
        return {"ref": "refs/tags/" + tag,
                "object": {"type": kind, "sha": commit, "url": "https://api.github.com/example"}}

    def test_release_targets_built_commit_and_publishes_only_after_upload(self):
        command = Mock(side_effect=["[]", "{}", "draft", "published"])
        url = publishing.publish_release(self.environment, self.archive, command)
        self.assertEqual(url, "https://github.com/example/nv/releases/tag/release-12-1")
        calls = command.call_args_list
        self.assertEqual(json.loads(calls[1].args[1]),
                         {"ref": "refs/tags/release-12-1", "sha": "a" * 40})
        creation, notes = calls[2].args
        self.assertEqual(creation[:4], ["release", "create", "release-12-1", str(self.archive)])
        self.assertIn("--verify-tag", creation)
        self.assertIn("--draft", creation)
        self.assertIn("Unsigned Intel Release", notes)
        self.assertIn("`2026.09-release`", notes)
        self.assertIn("`" + "a" * 40 + "`", notes)
        self.assertIn("https://github.com/example/nv/actions/runs/1234", notes)
        self.assertEqual(calls[3].args[0], ["release", "edit", "release-12-1", "--repo",
                                         "example/nv", "--draft=false", "--latest=false"])

    def test_master_pr_tags_nested_branches_and_near_matches_cannot_publish(self):
        cases = [("push", "refs/heads/master"),
                 ("push", "refs/heads/topic"),
                 ("push", "refs/heads/topic-release-candidate"),
                 ("push", "refs/heads/topic-Release"),
                 ("push", "refs/heads/codex/topic-release"),
                 ("push", "refs/tags/topic-release"),
                 ("pull_request", "refs/heads/topic-release"),
                 ("pull_request_target", "refs/heads/topic-release")]
        for event, ref in cases:
            with self.subTest(event=event, ref=ref):
                command = Mock()
                with self.assertRaises(ValueError):
                    publishing.publish_release(dict(self.environment, GITHUB_EVENT_NAME=event,
                                                    GITHUB_REF=ref), self.archive, command)
                command.assert_not_called()

    def test_matching_pushes_and_manual_builds_can_publish(self):
        for event in ("push", "workflow_dispatch"):
            for branch in ("smoke-release", "2026.09-release", "-release"):
                with self.subTest(event=event, branch=branch):
                    command = Mock(side_effect=["[]", "{}", "draft", "published"])
                    publishing.publish_release(dict(self.environment, GITHUB_EVENT_NAME=event,
                                                    GITHUB_REF="refs/heads/" + branch), self.archive, command)

    def test_branch_deletion_cannot_publish(self):
        event = Path(self.directory.name) / "event.json"
        event.write_text(json.dumps({"deleted": True}))
        command = Mock()
        with self.assertRaisesRegex(ValueError, "deletion"):
            publishing.publish_release(dict(self.environment, GITHUB_EVENT_PATH=str(event)),
                                       self.archive, command)
        command.assert_not_called()

    def test_api_failure_does_not_create_a_tag_or_release(self):
        command = Mock(side_effect=subprocess.CalledProcessError(1, "gh"))
        with self.assertRaises(subprocess.CalledProcessError):
            publishing.publish_release(self.environment, self.archive, command)
        self.assertEqual(command.call_count, 1)

    def test_tag_create_failure_does_not_publish(self):
        command = Mock(side_effect=["[]", subprocess.CalledProcessError(1, "gh")])
        with self.assertRaises(subprocess.CalledProcessError):
            publishing.publish_release(self.environment, self.archive, command)
        self.assertEqual(command.call_count, 2)

    def test_upload_failure_leaves_release_unpublished(self):
        command = Mock(side_effect=["[]", "{}", subprocess.CalledProcessError(1, "gh")])
        with self.assertRaises(subprocess.CalledProcessError):
            publishing.publish_release(self.environment, self.archive, command)
        self.assertEqual(command.call_count, 3)

    def test_tag_at_same_commit_is_reused(self):
        command = Mock(side_effect=[json.dumps([self.reference()]), "draft", "published"])
        publishing.publish_release(self.environment, self.archive, command)
        self.assertEqual(command.call_count, 3)
        self.assertEqual(command.call_args_list[1].args[0][:2], ["release", "create"])

    def test_conflicting_and_annotated_tags_are_never_moved(self):
        for reference in (self.reference(commit="b" * 40), self.reference(kind="tag")):
            with self.subTest(reference=reference):
                command = Mock(return_value=json.dumps([reference]))
                with self.assertRaisesRegex(ValueError, "different target"):
                    publishing.publish_release(self.environment, self.archive, command)
                self.assertEqual(command.call_count, 1)

    def test_prefix_match_cannot_replace_exact_tag_check(self):
        command = Mock(side_effect=[json.dumps([self.reference(tag="release-12-10")]),
                                   "{}", "draft", "published"])
        publishing.publish_release(self.environment, self.archive, command)
        self.assertEqual(command.call_args_list[1].args[0][1:3], ["--method", "POST"])

    def test_failed_job_rerun_can_use_original_build_artifact_with_new_tag(self):
        command = Mock(side_effect=["[]", "{}", "draft", "published"])
        url = publishing.publish_release(dict(self.environment, GITHUB_RUN_ATTEMPT="2"), self.archive, command)
        self.assertTrue(url.endswith("/release-12-2"))
        self.assertIn(str(self.archive), command.call_args_list[2].args[0])

    def test_bad_metadata_or_missing_archive_cannot_publish(self):
        for key, value in (("GITHUB_RUN_NUMBER", "0"), ("GITHUB_RUN_ATTEMPT", "../1"),
                           ("GITHUB_RUN_ID", "x"), ("GITHUB_SHA", "master"),
                           ("GITHUB_REPOSITORY", "example"), ("GH_TOKEN", "")):
            with self.subTest(key=key):
                command = Mock()
                with self.assertRaises(ValueError):
                    publishing.publish_release(dict(self.environment, **{key: value}), self.archive, command)
                command.assert_not_called()
        for archive in (self.archive.with_name("missing.zip"),
                        self.archive.with_name("nvALT-macos-x86_64-99-1.zip")):
            command = Mock()
            with self.assertRaises(ValueError):
                publishing.publish_release(self.environment, archive, command)
            command.assert_not_called()


if __name__ == "__main__":
    unittest.main()
