#!/bin/sh

set -eu

# Batch jobs test multiple PRs together and have no single PULL_TITLE to verify.
if [ "${JOB_TYPE:-}" = "batch" ]; then
    echo "Skipping PR title verification for batch job."
    exit 0
fi

WIP_REGEX='^\W?WIP\W'
TAG_REGEX='^\[[[:alnum:]\._-]*\]'

trimmed_title=$(echo "$PULL_TITLE" | sed -E "s/${WIP_REGEX}//" | sed -E "s/${TAG_REGEX}//" | xargs)

trimmed_title=$(echo "$trimmed_title" | sed -E "s/:warning:/⚠/g")
trimmed_title=$(echo "$trimmed_title" | sed -E "s/:sparkles:/✨/g")
trimmed_title=$(echo "$trimmed_title" | sed -E "s/:bug:/🐛/g")
trimmed_title=$(echo "$trimmed_title" | sed -E "s/:book:/📖/g")
trimmed_title=$(echo "$trimmed_title" | sed -E "s/:rocket:/🚀/g")
trimmed_title=$(echo "$trimmed_title" | sed -E "s/:seedling:/🌱/g")

if echo "$trimmed_title" | grep -Eq '^(⚠|✨|🐛|📖|🚀|🌱)'; then
    echo "PR title is valid: $trimmed_title"
else
    echo "Error: No matching PR type indicator found in title."
    echo "You need to have one of these as the prefix of your PR title:"
    echo "- Breaking change: ⚠ (:warning:)"
    echo "- Non-breaking feature: ✨ (:sparkles:)"
    echo "- Patch fix: 🐛 (:bug:)"
    echo "- Docs: 📖 (:book:)"
    echo "- Release: 🚀 (:rocket:)"
    echo "- Infra/Tests/Other: 🌱 (:seedling:)"
    exit 1
fi

if echo "$trimmed_title" | grep -Eq '#[0-9]+'; then
    echo "Error: PR title should not contain issue or PR number."
    echo "Issue numbers belong in the PR body as either \"Fixes #XYZ\" (if it closes the issue or PR), or something like \"Related to #XYZ\" (if it's just related)."
    exit 1
fi
