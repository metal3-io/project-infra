#!/bin/sh
# Check links in markdown files changed by a PR.
# Port of .github/workflows/pr-link-check.yml. Runs from the PR repo's working
# dir, so that repo's .lycheeignore is picked up.

set -eu

# lychee image ships without git; needs root (job sets runAsUser: 0).
command -v git >/dev/null || apk add --no-cache git >/dev/null
git config --global --add safe.directory "$(pwd)"

files=$(git diff --name-only --diff-filter=d "${PULL_BASE_SHA}" HEAD -- '*.md')
echo "${files}"
[ -n "${files}" ] || exit 0

# lychee reads GITHUB_TOKEN from the env when set, same as the GHA job.
# shellcheck disable=SC2086
if ! lychee \
    --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Brave/131" \
    --root-dir "$(pwd)/" \
    --fallback-extensions md \
    --max-concurrency 8 \
    --max-retries 5 \
    --retry-wait-time 10 \
    --insecure \
    --exclude-all-private \
    --no-progress \
    ${files}; then
    cat <<'EOF'
Error: Link check failed! Please review the broken links reported above.
If valid links fail due to CAPTCHA, IP blocking, auth or rate limiting,
add them to .lycheeignore (one URL pattern per line).
EOF
    exit 1
fi
