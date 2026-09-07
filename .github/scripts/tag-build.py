#!/usr/bin/env python3
"""Tag the commit from a successful master build without moving existing tags."""

import json
import os
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def github_api(method, path, token, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    request = Request(
        "https://api.github.com" + path,
        data=data,
        method=method,
        headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
            "User-Agent": "nv-macos-ci",
        },
    )
    with urlopen(request, timeout=30) as response:
        return json.load(response)


def tag_build(environment, api=github_api):
    if environment.get("GITHUB_EVENT_NAME") not in {"push", "workflow_dispatch"}:
        raise ValueError("Only push and manual builds can create tags.")
    if environment.get("GITHUB_REF") != "refs/heads/master":
        raise ValueError("Only master builds can create tags.")

    repository = environment["GITHUB_REPOSITORY"]
    commit = environment["GITHUB_SHA"]
    number = environment["GITHUB_RUN_NUMBER"]
    token = environment["GH_TOKEN"]
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid repository name.")
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Invalid build commit.")
    if not re.fullmatch(r"[1-9][0-9]*", number):
        raise ValueError("Invalid workflow run number.")
    if not token:
        raise ValueError("GH_TOKEN is required.")

    tag = "build-" + number
    base = "/repos/" + repository + "/git"

    def existing_tag():
        try:
            return api("GET", base + "/ref/tags/" + tag, token)
        except HTTPError as error:
            error.close()
            if error.code != 404:
                raise
            return None

    def require_same_commit(reference):
        target = reference.get("object", {})
        if target.get("type") != "commit" or target.get("sha") != commit:
            raise ValueError(tag + " already exists with a different target.")

    existing = existing_tag()
    if existing is not None:
        require_same_commit(existing)
        return tag

    try:
        api("POST", base + "/refs", token, {"ref": "refs/tags/" + tag, "sha": commit})
    except HTTPError as error:
        error.close()
        if error.code != 422:
            raise
        # A concurrent retry can create the same reference after the lookup.
        existing = existing_tag()
        if existing is None:
            raise
        require_same_commit(existing)
    return tag


if __name__ == "__main__":
    try:
        tag = tag_build(os.environ)
        print("Build tag: " + tag)
        if os.environ.get("GITHUB_STEP_SUMMARY"):
            with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
                summary.write("Build tag: `" + tag + "`\n")
    except (KeyError, ValueError, HTTPError, URLError) as error:
        print("Automatic tagging failed: " + str(error), file=sys.stderr)
        sys.exit(1)
