#!/usr/bin/env bash
set -euo pipefail

# Usage: get_latest_tag.sh <module-list-url> <release-branch> [excludePattern]
# Example: get_latest_tag.sh https://proxy.golang.org/github.com/metal3-io/cluster-api-provider-metal3/@v/list release-1.10 'beta|rc|alpha|pre'

get_latest_release_from_goproxy() {
  local listUrl="${1:?no list url given}"        # full @v/list URL
  local release="${2:?no release given}"         # e.g. release-1.10
  local exclude="${3:-}"                         # optional exclude regex

  release="${release/release-/v}."
  local release_tag
  if [[ -z "${exclude}" ]]; then
    release_tag=$(curl -s "${listUrl}" \
      | sed '/-/!{s/$/_/}' \
      | sort -rV \
      | sed 's/_$//' \
      | grep -m1 "^${release}")
  else
    release_tag=$(curl -s "${listUrl}" \
      | sort -rV \
      | grep -vE "${exclude}" \
      | grep -m1 "^${release}")
  fi

  if [[ -z "${release_tag}" ]]; then
    echo "Error: release not found for prefix ${release} in ${listUrl}" >&2
    exit 1
  fi
  echo "${release_tag}"
}

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <module-list-url> <release-branch> [excludePattern]" >&2
  exit 2
fi

get_latest_release_from_goproxy "$1" "$2" "${3:-}"
