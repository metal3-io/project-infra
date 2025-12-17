#!/usr/bin/env python3
"""
Dump required tests out of prow config in human (and machine) readable format.
Crosscheck versus GitHub branch protection settings and print discrepancies.
Also validates that release branches have proper protections and lock status.
"""

from argparse import ArgumentParser
from collections import defaultdict
import os
import re
import sys
from typing import DefaultDict, Dict, List, Optional, Set, Tuple

import requests
import yaml


VERSION_SUPPORT_URL = (
    "https://raw.githubusercontent.com/metal3-io/metal3-docs/main/"
    "docs/user-guide/src/version_support.md"
)
MAX_UNLOCKED_RELEASE_BRANCHES = 3
RELEASE_BRANCH_PATTERN = re.compile(r"^release-(\d+)\.(\d+)(?:\.(\d+))?$")


def gh_headers(token: str) -> Dict[str, str]:
    """Standard GitHub API headers."""
    return {"Authorization": f"token {token}", "Accept": "application/vnd.github.v3+json"}


def check_github_token_scopes(token: str) -> Tuple[bool, str]:
    """Check if token has required scopes. Returns (ok, error_message)."""
    try:
        response = requests.get("https://api.github.com/user", headers=gh_headers(token), timeout=30)
        response.raise_for_status()
        scopes = {s.strip() for s in response.headers.get("X-OAuth-Scopes", "").split(",") if s.strip()}

        if not ("repo" in scopes or "public_repo" in scopes):
            return False, f"Token missing 'repo' scope. Has: {', '.join(scopes) or 'none'}"
        if not ("read:org" in scopes or "admin:org" in scopes):
            return False, f"Token missing 'read:org' scope. Has: {', '.join(scopes) or 'none'}"
        return True, ""
    except requests.exceptions.HTTPError as e:
        if e.response.status_code == 401:
            return False, "Token is invalid or expired"
        return False, f"Error validating token: {e}"
    except requests.exceptions.RequestException as e:
        return False, f"Error validating token: {e}"


def get_external_branchprotection(data: dict) -> DefaultDict[str, List[str]]:
    """Extract branch protection jobs from prow config branch-protection section."""
    result: DefaultDict[str, List[str]] = defaultdict(list)
    for org, org_data in data.get("orgs", {}).items():
        for repo, repo_data in org_data.get("repos", {}).items():
            for branch, branch_data in repo_data.get("branches", {}).items():
                checks = branch_data.get("required_status_checks", {}).get("contexts", [])
                result[f"{org}/{repo}/{branch}"].extend(checks)
    return result


def get_prow_branchprotection(data: dict) -> DefaultDict[str, List[str]]:
    """Extract required (non-optional, not always_run) tests from presubmits."""
    result: DefaultDict[str, List[str]] = defaultdict(list)
    for orgrepo, jobs in data.items():
        for job in jobs:
            if job.get("optional") or job.get("always_run") is not False:
                continue
            name = job.get("name")
            for branch in job.get("branches", ["ALL BRANCHES"]):
                result[f"{orgrepo}/{branch}"].append(name)
    return result


def get_all_prow_repos_and_branches(data: dict) -> DefaultDict[str, Set[str]]:
    """Get all repos and their explicitly configured branches from presubmits."""
    result: DefaultDict[str, Set[str]] = defaultdict(set)
    for orgrepo, jobs in data.items():
        result[orgrepo]  # Ensure repo exists even without explicit branches
        for job in jobs:
            result[orgrepo].update(job.get("branches", []))
    return result


def get_github_default_branch(owner: str, repo: str, token: str) -> str:
    """Get default branch for repo."""
    try:
        response = requests.get(
            f"https://api.github.com/repos/{owner}/{repo}",
            headers=gh_headers(token), timeout=30
        )
        response.raise_for_status()
        return response.json()["default_branch"]
    except requests.exceptions.RequestException as e:
        sys.exit(f"Error getting default branch: {e}")


def get_github_branches(owner: str, repo: str, token: str) -> List[Dict]:
    """Get all branches for a repository with pagination."""
    branches = []
    try:
        page = 1
        while True:
            response = requests.get(
                f"https://api.github.com/repos/{owner}/{repo}/branches",
                headers=gh_headers(token), timeout=30,
                params={"per_page": 100, "page": page}
            )
            response.raise_for_status()
            data = response.json()
            if not data:
                break
            branches.extend(data)
            page += 1
    except requests.exceptions.RequestException as e:
        print(f"Warning: Could not fetch branches for {owner}/{repo}: {e}")
    return branches


def get_branch_protection_settings(
    owner: str, repo: str, branch: str, token: str
) -> Tuple[Optional[Dict], str]:
    """
    Get branch protection settings.
    Returns (settings, error) where error is "" on success, "access_denied" on 403.
    """
    try:
        response = requests.get(
            f"https://api.github.com/repos/{owner}/{repo}/branches/{branch}/protection",
            headers=gh_headers(token), timeout=30
        )
        if response.status_code == 404:
            return None, ""
        if response.status_code == 403:
            return None, "access_denied"
        response.raise_for_status()
        return response.json(), ""
    except requests.exceptions.RequestException as e:
        return None, str(e)


def get_github_required_checks(owner: str, repo: str, branch: str, token: str) -> List[str]:
    """Get required status checks configured in GitHub for a branch."""
    if branch == "ALL BRANCHES":
        branch = get_github_default_branch(owner, repo, token)
    try:
        response = requests.get(
            f"https://api.github.com/repos/{owner}/{repo}/branches/{branch}/protection",
            headers=gh_headers(token), timeout=30
        )
        response.raise_for_status()
        checks = response.json().get("required_status_checks")
        return checks.get("contexts", []) if checks else []
    except requests.exceptions.HTTPError:
        return []
    except requests.exceptions.RequestException as e:
        sys.exit(f"Error: {e}")


def validate_protection_settings(settings: Dict, prefix: str) -> List[str]:
    """Validate branch protection settings for unlocked branches."""
    issues = []

    pr_reviews = settings.get("required_pull_request_reviews")
    if not pr_reviews:
        issues.append(f"{prefix}: require pull request reviews is DISABLED")
    elif not pr_reviews.get("dismiss_stale_reviews"):
        issues.append(f"{prefix}: dismiss stale PR approvals when new commits pushed is DISABLED")

    if not settings.get("required_status_checks"):
        issues.append(f"{prefix}: required status checks is DISABLED")

    if not settings.get("enforce_admins", {}).get("enabled"):
        issues.append(f"{prefix}: do not allow admin bypass is DISABLED")

    if settings.get("allow_force_pushes", {}).get("enabled"):
        issues.append(f"{prefix}: allow force pushes is ENABLED (should be disabled)")

    if settings.get("allow_deletions", {}).get("enabled"):
        issues.append(f"{prefix}: allow deletions is ENABLED (should be disabled)")

    return issues


def get_release_branches(branches: List[Dict]) -> List[str]:
    """Filter and sort release branches (newest first)."""
    releases = []
    for b in branches:
        match = RELEASE_BRANCH_PATTERN.match(b.get("name", ""))
        if match:
            version = (int(match.group(1)), int(match.group(2)), int(match.group(3) or 0))
            releases.append((b["name"], version))
    releases.sort(key=lambda x: x[1], reverse=True)
    return [name for name, _ in releases]


def fetch_ironic_version_support() -> Dict[str, str]:
    """Fetch ironic-image version support table from metal3-docs."""
    try:
        response = requests.get(VERSION_SUPPORT_URL, timeout=30)
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        print(f"Warning: Could not fetch version support table: {e}")
        return {}

    result = {}
    in_ironic_section = False
    for line in response.text.split("\n"):
        if "## Ironic-image" in line:
            in_ironic_section = True
        elif in_ironic_section and line.startswith("##"):
            break
        elif in_ironic_section and line.startswith("|"):
            parts = [p.strip() for p in line.split("|")]
            if len(parts) >= 4 and parts[1].startswith("v"):
                result[parts[1]] = parts[2]
    return result


def ironic_branch_to_version(branch: str) -> Optional[str]:
    """Convert branch name to version (e.g., 'release-33.0' -> 'v33.0')."""
    match = re.match(r"^release-(\d+\.\d+)$", branch)
    return f"v{match.group(1)}" if match else None


def check_branch(
    owner: str, repo: str, branch: str, branch_info: Dict, token: str,
    required_checks: List[str], is_release: bool, prow_branches: Set[str],
    release_idx: int = 0, ironic_versions: Optional[Dict[str, str]] = None,
) -> Tuple[List[str], bool]:
    """
    Check a branch for protection and configuration issues.
    Returns (issues_list, is_locked).
    """
    issues = []
    prefix = f"{owner}/{repo}/{branch}"

    def add_issue(msg: str):
        issues.append(f"{prefix}: {msg}")
        print(f"- {branch}: {msg}")

    # Check protection exists
    if not branch_info.get("protected"):
        add_issue("MISSING BRANCH PROTECTION")
        return issues, False

    # Get protection settings
    settings, error = get_branch_protection_settings(owner, repo, branch, token)
    if error == "access_denied":
        add_issue("NO ADMIN ACCESS to check branch protection")
        return issues, False
    if error:
        print(f"- {branch}: error fetching protection: {error}")
        return issues, False
    if not settings:
        print(f"- {branch}: no protection configured")
        return issues, False

    is_locked = settings.get("lock_branch", {}).get("enabled", False)

    # Release branch lock status checks
    if is_release:
        if is_locked:
            if branch in prow_branches:
                add_issue("LOCKED branch has prow tests configured")
        else:
            if branch not in prow_branches:
                add_issue("UNLOCKED branch has no prow tests configured")

            # Check if should be locked
            if repo == "ironic-image" and ironic_versions:
                version = ironic_branch_to_version(branch)
                if version:
                    status = ironic_versions.get(version)
                    if status == "EOL":
                        add_issue("EOL version should be LOCKED")
                    elif not status:
                        add_issue("version not in support table, should be LOCKED")
            elif release_idx >= MAX_UNLOCKED_RELEASE_BRANCHES:
                add_issue(f"should be LOCKED (only latest {MAX_UNLOCKED_RELEASE_BRANCHES} allowed)")

        # Check if locked but should be active (ironic only)
        if is_locked and repo == "ironic-image" and ironic_versions:
            version = ironic_branch_to_version(branch)
            if version:
                status = ironic_versions.get(version)
                if status in ("Supported", "Tested"):
                    add_issue(f"{status} version should be UNLOCKED")

    # Validate protection settings (skip for locked)
    if not is_locked:
        for issue in validate_protection_settings(settings, prefix):
            issues.append(issue)
            print(f"- {branch}: {issue.split(': ', 1)[1]}")

    # Check required tests (skip for locked release branches)
    if not (is_release and is_locked):
        gh_checks = get_github_required_checks(owner, repo, branch, token)
        for check in required_checks:
            if check not in gh_checks:
                add_issue(f"test '{check}' MISSING FROM GITHUB")
        for check in gh_checks:
            if check not in required_checks:
                add_issue(f"test '{check}' EXTRA IN GH (or missing from prow)")

    # Print OK if no issues
    if not issues:
        status = f"ok ({('locked' if is_locked else 'unlocked')})" if is_release else "ok"
        print(f"- {branch}: {status}")

    return issues, is_locked


def parse_args():
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

    # Check token scopes if token is provided
    if github_token:
        has_scopes, error_msg = check_github_token_scopes(github_token)
        if not has_scopes:
            print(f"Error: {error_msg}", file=sys.stderr)
            print("\nTo check branch protections, you need:", file=sys.stderr)
            print("  - A token with 'repo' and 'read:org' scopes", file=sys.stderr)
            sys.exit(1)

    with open(args.config, "r", encoding="utf-8") as fh:
        parsed_data = yaml.safe_load(fh)

    # protection can come from two places: branch-protection and presubmits
    branchprotection = parsed_data.get("branch-protection", {})
    required = get_external_branchprotection(branchprotection)
    presubmits = parsed_data.get("presubmits", {})
    pre_submit = get_prow_branchprotection(presubmits)
    required.update(pre_submit)

    # Collect ALL prow-configured repos and branches (for release branch checks)
    all_prow_branches: DefaultDict[str, Set[str]] = defaultdict(set)
    prow_branches = get_all_prow_repos_and_branches(presubmits)
    for orgrepo, branches in prow_branches.items():
        all_prow_branches[orgrepo].update(branches)

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
                    # Also collect all prow repos and branches
                    prow_branches = get_all_prow_repos_and_branches(presubmits)
                    for orgrepo, branches in prow_branches.items():
                        all_prow_branches[orgrepo].update(branches)

    # Organize required checks by repo and branch
    required_by_repo: DefaultDict[str, DefaultDict[str, List[str]]] = defaultdict(
        lambda: defaultdict(list)
    )
    for target, checks in required.items():
        parts = target.split("/")
        if len(parts) >= 3:
            required_by_repo[f"{parts[0]}/{parts[1]}"][parts[2]].extend(checks)

    if not github_token:
        print("=" * 60)
        print("Required Tests (no GitHub token - skipping validation)")
        print("=" * 60 + "\n")
        for target, checks in sorted(required.items()):
            print(f"{target}:")
            for check in checks:
                print(f"- {check}")
            print()
        return

    ironic_versions = fetch_ironic_version_support()
    all_issues: List[str] = []

    for orgrepo in sorted(all_prow_branches.keys()):
        parts = orgrepo.split("/")
        if len(parts) != 2:
            continue
        owner, repo = parts
        prow_branches_for_repo = all_prow_branches[orgrepo]
        req_for_repo = required_by_repo.get(orgrepo, defaultdict(list))

        print("=" * 60)
        print(orgrepo)

        branches = get_github_branches(owner, repo, github_token)
        if not branches:
            print("- Warning: Could not fetch branches\n")
            continue

        # Check default branch
        default_name = get_github_default_branch(owner, repo, github_token)
        default_info = next((b for b in branches if b["name"] == default_name), None)
        if default_info:
            req = req_for_repo.get(default_name, []) + req_for_repo.get("ALL BRANCHES", [])
            issues, _ = check_branch(
                owner, repo, default_name, default_info, github_token,
                req, is_release=False, prow_branches=prow_branches_for_repo
            )
            all_issues.extend(issues)

        # Check release branches (newest to oldest), stop after 2 consecutive locked
        ironic_support = ironic_versions if repo == "ironic-image" else None
        consecutive_locked = 0

        for i, branch_name in enumerate(get_release_branches(branches)):
            branch_info = next((b for b in branches if b["name"] == branch_name), None)
            if not branch_info:
                continue

            req = req_for_repo.get(branch_name, []) + req_for_repo.get("ALL BRANCHES", [])
            issues, is_locked = check_branch(
                owner, repo, branch_name, branch_info, github_token, req,
                is_release=True, prow_branches=prow_branches_for_repo,
                release_idx=i, ironic_versions=ironic_support
            )
            all_issues.extend(issues)

            consecutive_locked = consecutive_locked + 1 if is_locked else 0
            if consecutive_locked >= 2:
                break

        print()

    # Summary
    print("=" * 60)
    print("Summary")
    print("=" * 60)
    if all_issues:
        print(f"Found {len(all_issues)} issue(s):")
        for issue in all_issues:
            print(f"- {issue}")
    else:
        print("All checks passed!")
    print()


if __name__ == "__main__":
    main()
