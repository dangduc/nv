#!/usr/bin/env python3
"""Publish an unsigned app from a successful *-release branch build."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys


def gh(arguments, payload=None):
    result = subprocess.run(
        ["gh", *arguments], input=payload, text=True, check=True, stdout=subprocess.PIPE
    )
    return result.stdout


def publish_release(environment, archive, command=gh):
    if environment.get("GITHUB_EVENT_NAME") not in {"push", "workflow_dispatch"}:
        raise ValueError("Only push and manual builds can publish releases.")
    ref = environment.get("GITHUB_REF", "")
    if not re.fullmatch(r"refs/heads/[^/]*-release", ref):
        raise ValueError("Only branches matching *-release can publish releases.")
    if environment.get("GITHUB_EVENT_PATH"):
        event = json.loads(Path(environment["GITHUB_EVENT_PATH"]).read_text())
        if event.get("deleted"):
            raise ValueError("Branch deletion cannot publish a release.")

    repository = environment["GITHUB_REPOSITORY"]
    commit = environment["GITHUB_SHA"]
    number = environment["GITHUB_RUN_NUMBER"]
    attempt = environment["GITHUB_RUN_ATTEMPT"]
    run_id = environment["GITHUB_RUN_ID"]
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid repository name.")
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Invalid build commit.")
    if any(not re.fullmatch(r"[1-9][0-9]*", value) for value in (number, attempt, run_id)):
        raise ValueError("Invalid workflow run metadata.")
    if not environment.get("GH_TOKEN"):
        raise ValueError("GH_TOKEN is required.")
    archive = Path(archive)
    if not archive.is_file() or not re.fullmatch(
            r"nvALT-macos-x86_64-" + number + r"-[1-9][0-9]*\.zip", archive.name):
        raise ValueError("The app archive must come from this workflow run.")

    tag = "release-" + number + "-" + attempt
    base = "repos/" + repository + "/git"
    references = json.loads(command(["api", base + "/matching-refs/tags/" + tag]))
    existing = next((ref for ref in references if ref["ref"] == "refs/tags/" + tag), None)
    if existing:
        target = existing.get("object", {})
        if target.get("type") != "commit" or target.get("sha") != commit:
            raise ValueError(tag + " already exists with a different target.")
    else:
        command(["api", "--method", "POST", base + "/refs", "--input", "-"],
                json.dumps({"ref": "refs/tags/" + tag, "sha": commit}))

    branch = ref.removeprefix("refs/heads/")
    notes = (
        "Unsigned Intel Release build of nvALT. Apple Silicon requires Rosetta.\n\n"
        "This app is not code-signed or notarized.\n\n"
        f"Branch: `{branch}`\n\nCommit: `{commit}`\n\n"
        f"[Build log](https://github.com/{repository}/actions/runs/{run_id})\n"
    )
    # Upload into a draft first, so a failed upload cannot publish an empty release.
    command(["release", "create", tag, str(archive), "--repo", repository,
             "--verify-tag", "--draft", "--title", f"nvALT {branch} (build {number}.{attempt})",
             "--notes-file", "-"], notes)
    command(["release", "edit", tag, "--repo", repository, "--draft=false", "--latest=false"])
    return f"https://github.com/{repository}/releases/tag/{tag}"


if __name__ == "__main__":
    try:
        url = publish_release(os.environ, sys.argv[1])
        print("Release: " + url)
        if os.environ.get("GITHUB_STEP_SUMMARY"):
            with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
                summary.write("[Download the unsigned release](" + url + ")\n")
    except (KeyError, ValueError, OSError, subprocess.CalledProcessError) as error:
        print("Release publication failed: " + str(error), file=sys.stderr)
        sys.exit(1)
