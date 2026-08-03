#!/bin/bash
set -euo pipefail

debug() {
    if [[ "${DEBUG}" == true ]]; then
        echo "[DEBUG] $*" >&2
    fi
}

distance_from_base() {
    local BASE="$1"
    local COUNT; COUNT=$(git rev-list --count "${BASE}"..HEAD)
    if [[ "${COUNT}" -gt 0 ]]; then
        local SHORT; SHORT=$(git rev-parse --short HEAD)
        echo "-dev.${COUNT}+${SHORT}"
    fi
}

DEBUG=false
IGNORE_GTAGS=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)              DEBUG=true ;;
        --nogtag)             IGNORE_GTAGS=true ;;
        --resolved_refname=*) RESOLVED_REFNAME="${1#--resolved_refname=}" ;;
        --resolved_ref=*)     RESOLVED_REF="${1#--resolved_ref=}" ;;
        *)                    echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

RESOLVED_REFNAME="${RESOLVED_REFNAME:-$(git rev-parse --abbrev-ref HEAD)}"
RESOLVED_REF="${RESOLVED_REF:-$(git rev-parse HEAD)}"
# Defaults to short ref combined with parser friendly branch name
RETURN_VAL="${RESOLVED_REF:0:7}_${RESOLVED_REFNAME//\//-}"

if [[ "${IGNORE_GTAGS}" == false ]]; then
    # Determine the Git tag with the highest version number in the repo
    LATEST_GTAG=$(git tag --sort=-version:refname | head -1)
    if [[ -z "${LATEST_GTAG}" ]]; then
        echo "ERROR: No tags found in repository" >&2
        exit 1
    fi
    LATEST_GTAG_VERSION="${LATEST_GTAG#v}"
    debug "LATEST_GTAG_VERSION=${LATEST_GTAG_VERSION}"
    # Next expected version based on heuristic
    IFS='.' read -r MAJOR MINOR PATCH <<< "${LATEST_GTAG_VERSION}"
    NEXT_MINOR="${MAJOR}.$((MINOR + 1)).0"
    debug "NEXT EXPECTED GLOBAL MINOR=${NEXT_MINOR}"
    # Determine common ancestor with latest Git tag
    BASE="$(git merge-base HEAD "${LATEST_GTAG}")" || {
        echo "ERROR: current branch and latest tag have no common ancestor" >&2
        exit 1
    }
    debug "COMMON BASE WITH NEXT EXPECTED MINOR=${BASE}"
fi

if [[ "${RESOLVED_REFNAME}" == "main" ]]; then
    # Main branches are generally not tagged
    debug "Main branch detected!"
    if [[ "${IGNORE_GTAGS}" == false ]]; then
        DELTA="$(distance_from_base "${BASE}")"
        if [[ -n "${DELTA}" ]]; then
            RETURN_VAL="${NEXT_MINOR}${DELTA}"
        else
            RETURN_VAL="${LATEST_GTAG_VERSION}"
        fi
    fi
elif [[ "${RESOLVED_REFNAME}" =~ ^release- ]]; then
    # Release branches have proper tags
    debug "Release branch detected!"
    BRANCH_MINOR="${RESOLVED_REFNAME#release-}"
    debug "Release branch version: ${BRANCH_MINOR}"
    if [[ "${BRANCH_MINOR}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        BRANCH_MINOR="${BRANCH_MINOR%.[0-9]*}"
    fi
    debug "Branch minor: ${BRANCH_MINOR}"
    CURRENT_TAG="$(git describe --tags --abbrev=0)" || {
        debug "No tags on release branch: ${RESOLVED_REFNAME}"
        CURRENT_TAG="NOTAG"
    }
    TAG_MINOR="${CURRENT_TAG#v}"
    TAG_MINOR="${TAG_MINOR%.[0-9]*}"
    debug "Tag minor: ${TAG_MINOR}"

    if [[ "${CURRENT_TAG}" != "NOTAG" ]] && [[ "${IGNORE_GTAGS}" == "false" ]];
    then
        if [[ "${BRANCH_MINOR}" == "${TAG_MINOR}" ]]; then
            # Pre release of a patch, counted from last tag on branch
            IFS='.' read -r MAJOR MINOR PATCH <<< "${CURRENT_TAG#v}"
            debug "PARSED BRANCH TAG VERSION=${MAJOR}.${MINOR}.${PATCH}"
            NEXT_PATCH="${MAJOR}.${MINOR}.$((PATCH + 1))"
            PATCH_BASE="$(git merge-base HEAD "${CURRENT_TAG}")"
            DELTA="$(distance_from_base "${PATCH_BASE}")"
            if [[ -n "${DELTA}" ]]; then
                RETURN_VAL="${NEXT_PATCH}${DELTA}"
            else
                RETURN_VAL="${CURRENT_TAG#v}"
            fi
        else
            # Pre release of minor, counted from common base with latest tag
            # This is very similar to what main branch would produce with
            # different distance because the HEAD is on a release branch
            RETURN_VAL="${BRANCH_MINOR}.0$(distance_from_base "${BASE}")"
        fi
    fi
fi

# Final fallback option:
# script was called on a branch other than main or release branch
# --nogtag was used but there were no local tags on target branch
# repo has no tags at all
echo "${RETURN_VAL}"

