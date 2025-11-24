#!/usr/bin/env bash
set -euo pipefail

# Usage: get_last_n_release_branches.sh <repo-url> [count]
# Example: get_last_n_release_branches.sh https://github.com/metal3-io/cluster-api-provider-metal3.git 3

REPO_URL="${1:?Usage: $0 <repo-url> [count]}"
COUNT="${2:-2}"

# Validate COUNT is a positive integer
if ! [[ "${COUNT}" =~ ^[0-9]+$ ]] || [ "${COUNT}" -lt 1 ]; then
  echo "Count must be a positive integer (given: ${COUNT})" >&2
  exit 1
fi

git ls-remote --heads "${REPO_URL}" \
  | awk -F'/' '/refs\/heads\/release-/ {print $NF}' \
  | sort -V \
  | tail -n "${COUNT}"
