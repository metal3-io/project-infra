#!/usr/bin/env python3
"""
Dump required tests out of prow config in human (and machine) readable format.
Crosscheck versus GitHub branch protection settings and print discrepancies.
"""

from argparse import Namespace, ArgumentParser
from collections import defaultdict
import os
import sys
from typing import DefaultDict, List

import requests
import yaml


def get_external_branchprotection(data: dict) -> DefaultDict[str, List[str]]:
    """print external branch protection jobs"""
    protected_repos: DefaultDict[str, List[str]] = defaultdict(list)

    for org, org_data in data.get("orgs", {}).items():
        for repo, repo_data in org_data.get("repos", {}).items():
            for branch, branch_data in repo_data.get("branches", {}).items():
                required_checks = branch_data.get("required_status_checks", {}).get("contexts", [])
                key = f"{org}/{repo}/{branch}"
                protected_repos.setdefault(key, []).extend(required_checks)

    return protected_repos


def get_prow_branchprotection(data: dict) -> DefaultDict[str, List[str]]:
    """get prow required tests"""
    protected_repos: DefaultDict[str, List[str]] = defaultdict(list)

    for orgrepo, orgrepo_data in data.items():
        for test_data in orgrepo_data:
            if test_data.get("optional") is not True:
                required_check = test_data.get("name")
                # skip all tests that are always_run
                if test_data.get("always_run") is not False:
                    continue
                for branch in test_data.get("branches", ["ALL BRANCHES"]):
                    key = f"{orgrepo}/{branch}"
                    protected_repos.setdefault(key, []).append(required_check)

    return protected_repos


def get_github_branch_protection(owner: str, repo: str, branch: str, token: str) -> List:
    """
    Check branch protection settings for a specific branch in a GitHub repository.
    """
    # this is a hack required due input data format
    if branch == "ALL BRANCHES":
        branch = get_github_default_branch(owner=owner, repo=repo, token=token)

    headers = {"Authorization": f"token {token}", "Accept": "application/vnd.github.v3+json"}
    url = f"https://api.github.com/repos/{owner}/{repo}/branches/{branch}/protection"

    try:
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()

        if response.status_code == 200:
            settings = response.json()
            if "required_status_checks" in settings:
                status_checks = settings["required_status_checks"]
                if status_checks:
                    return status_checks.get("contexts", [])
    except requests.exceptions.RequestException as ex:
        sys.exit(f"Error: {str(ex)}")
    return []


def get_github_default_branch(owner: str, repo: str, token: str) -> str:
    """
    Get default branch for repo
    """
    headers = {"Authorization": f"token {token}", "Accept": "application/vnd.github.v3+json"}
    url = f"https://api.github.com/repos/{owner}/{repo}"

    try:
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()
        return response.json()["default_branch"]
    except requests.exceptions.RequestException as e:
        sys.exit(f"Error: {str(e)}")


def parse_args() -> Namespace:
    """parse arguments"""
    parser = ArgumentParser(
        description="Dump required tests out of Prow config.yaml and job-config"
    )
    parser.add_argument(
        "--config",
        type=str,
        default="prow/config/config.yaml",
        help="""
        Prow's config.yaml (if you define presubmit separately, see --job-dir)
        """,
    )
    parser.add_argument(
        "--job-dir",
        type=str,
        default="prow/config/jobs/",
        help="""
        folder containing additional job definition yaml files. This will be
        searched recursively for YAML files.
        """,
    )
    parser.add_argument(
        "--token",
        type=str,
        help="""
        GitHub API token. Need to have maintainer's read access to all repos.
        Can also be defined via GITHUB_TOKEN environment variable. Leave empty
        if you do not have enough permissions to skip GitHub API calls.
        """,
    )

    args = parser.parse_args()
    return args


def main():
    """print out required jobs"""
    args = parse_args()
    github_token = os.getenv("GITHUB_TOKEN") or args.token

    with open(args.config, "r", encoding="utf-8") as fh:
        parsed_data = yaml.safe_load(fh)

    # protection can come from two places: branch-protection and presubmits
    branchprotection = parsed_data.get("branch-protection", {})
    required = get_external_branchprotection(branchprotection)
    presubmits = parsed_data.get("presubmits", {})
    pre_submit = get_prow_branchprotection(presubmits)
    required.update(pre_submit)

    # parse job-dir as well, as we have split Prow config into per branch jobs
    if args.job_dir:
        for root, _, filenames in os.walk(args.job_dir):
            for filename in filenames:
                if not filename.endswith(".yaml"):
                    continue
                with open(os.path.join(root, filename), "r", encoding="utf-8") as fh:
                    parsed_data = yaml.safe_load(fh)
                    presubmits = parsed_data.get("presubmits", {})
                    pre_submit = get_prow_branchprotection(presubmits)
                    required.update(pre_submit)

    # print out the results and crosscheck Github settings
    for target, checks in sorted(required.items()):
        gh_checks = []
        if github_token:
            owner, repo, branch = target.split("/")
            gh_checks = get_github_branch_protection(
                owner=owner, repo=repo, branch=branch, token=github_token
            )
        print(f"{target}:")

        for check in checks:
            if not github_token or check in gh_checks:
                print(f"- {check}")
            else:
                print(f"- {check} (MISSING FROM GITHUB!)")

        for check in gh_checks:
            if check not in checks:
                print(f"- {check} (EXTRA IN GH, OR MISSING FROM PROW CONFIG!)")
        print()


if __name__ == "__main__":
    main()
