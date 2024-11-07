#!/usr/bin/env python3
"""
Dump required tests out of prow config in human (and machine) readable format
"""

from argparse import Namespace, ArgumentParser
from collections import defaultdict
from typing import DefaultDict, List

# pip3 install PyYAML
import yaml
import os


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


def parse_args() -> Namespace:
    """parse arguments"""
    parser = ArgumentParser(description="Dump required tests out of Prow config.yaml and job-config")
    parser.add_argument(
        "file",
        type=str,
        help="""
        Prow's config.yaml (if you define presubmit separately, see --job-dir)
        """,
    )
    parser.add_argument(
        "--job-dir",
        help="""
        folder containing additional job definition yaml files. This will be search recursively for yaml files.
        """,
    )
    args = parser.parse_args()
    return args


def main():
    """print out required jobs"""
    args = parse_args()

    with open(args.file, "r", encoding="utf-8") as fh:
        parsed_data = yaml.safe_load(fh)

    # protection can come from two places: branch-protection and presubmits
    branchprotection = parsed_data.get("branch-protection", {})
    required = get_external_branchprotection(branchprotection)
    presubmits = parsed_data.get("presubmits", {})
    pre_submit = get_prow_branchprotection(presubmits)
    required.update(pre_submit)

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

    for repo, checks in sorted(required.items()):
        print(f"{repo}:")
        for check in checks:
            print(f"- {check}")
        print()


if __name__ == "__main__":
    main()
