# Version checker script user guide

Generates SemVer-compliant version strings for the Metal3 project based on
the current Git branch, tags, and commit distance. Designed for CI pipelines
where container images and artifacts need meaningful, sortable version labels.

This script expects release tags to follow the SemVer format (e.g., `v1.2.3`).
It only generates SemVer-compliant versions on `main` and `release-*` branches.
All other branches fall back to `SHORTSHA_branchname` (7-char SHA prefix,
slashes replaced with dashes).

## Usage

```bash
./versioncheck.sh [OPTIONS]
```

## Options

| Option | Description |
|--------|-------------|
| `--debug` | Print debug information to stderr |
| `--nogtag` | Ignore global tags for version calculation. Useful for forks with custom tag strings. Falls back to `SHORTSHA_refname` when tags outside of HEAD's branch are irrelevant or have no common ancestry with the latest tag's branch |
| `--resolved_refname=<name>` | Override the branch/ref name (default: current branch from `git rev-parse --abbrev-ref HEAD`) |
| `--resolved_ref=<sha>` | Override the commit SHA (default: current HEAD from `git rev-parse HEAD`) |

Options can be provided in any order.

## Examples

```bash
# Auto-detect branch and ref
./versioncheck.sh

# With debug output
./versioncheck.sh --debug

# Simulate running on main branch
./versioncheck.sh --resolved_refname=main

# Simulate a release branch
./versioncheck.sh --resolved_refname=release-1.2

# Fork with non-standard tags
./versioncheck.sh --nogtag
```

## Version Output by Use Case

| # | Scenario | Output | SemVer |
|---|----------|--------|--------|
| 1 | `main`, ahead of latest tag | `MAJOR.(MINOR+1).0-dev.N+SHA` | ✅ |
| 2 | `main`, at merge-base (0 distance) | `MAJOR.MINOR.PATCH` | ✅ |
| 3 | `main` + `--nogtag` | `a1b2c3d_main` | fallback |
| 4 | `release-X.Y`, tag matches, ahead of tag | `MAJOR.MINOR.(PATCH+1)-dev.N+SHA` | ✅ |
| 5 | `release-X.Y`, exactly on tag | `MAJOR.MINOR.PATCH` | ✅ |
| 6 | `release-X.Y.Z` (3-segment branch name) | Strips patch → same as #4/#5 | ✅ |
| 7 | `release-X.Y`, tag minor ≠ branch minor | `X.Y.0-dev.N+SHA` | ✅ |
| 8 | `release-X.Y`, tag mismatch + `--nogtag` | `a1b2c3d_release-X.Y` | fallback |
| 9 | `release-*`, no tags on branch and no reachable ancestor with latest tag | `a1b2c3d_release-X.Y` | fallback |
| 10 | No common ancestor with latest tag in the repo (`--nogtag` avoids this issue) | Error + exit 1 | N/A |
| 11 | Feature / other branch (e.g. `feature/foo`) | `a1b2c3d_feature-foo` | fallback |
| 12 | No tags in repo (without `--nogtag`) | Error + exit 1 | N/A |
| 13 | No tags in repo + `--nogtag` | `a1b2c3d_branchname` | fallback |

Rows marked **fallback** produce a non-SemVer `SHORTSHA_branchname` identifier
(7-char SHA, slashes replaced with dashes) for traceability when a proper
version cannot be determined.

## SemVer Compliance

Output follows [SemVer 2.0.0](https://semver.org/) format:
`MAJOR.MINOR.PATCH[-PRERELEASE][+BUILDMETADATA]`

- **Pre-release** (`-dev.N`): commit count from base, ensures correct sort
  order between dev builds
- **Build metadata** (`+SHA`): short commit hash for traceability, ignored
  for precedence
- **Precedence**: `1.2.0 < 1.3.0-dev.5+abc123 < 1.3.0`

## Requirements

- Git repository with at least one SemVer tag (e.g., `v1.0.0`) unless
  `--nogtag` is used
- Full clone (not shallow) for accurate commit counts and `merge-base`
- In all cases, generating SemVer for a main or release branch requires:
   - A tag reachable on the branch as an ancestor of the HEAD
   - OR a common ancestor between the HEAD and the latest tag in the repo
- `--nogtag` bypasses the tag existence requirement, producing a
  fallback version instead of an error for repos that lack tags completely
