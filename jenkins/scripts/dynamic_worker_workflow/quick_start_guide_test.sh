#!/usr/bin/env bash

set -eux

# Description:
#   Runs the metal3-docs Quick Start Guide test in a dynamic jenkins worker.
# Usage:
#   ./quick_start_guide_test.sh

export REPO_ORG="${REPO_ORG:-metal3-io}"
export REPO_NAME="${REPO_NAME:-metal3-docs}"
export REPO_BRANCH="${REPO_BRANCH:-main}"
export PR_ID="${PR_ID:-}"
export UPDATED_REPO="${UPDATED_REPO:-https://github.com/metal3-io/metal3-docs.git}"
export UPDATED_BRANCH="${UPDATED_BRANCH:-main}"

# Clone the metal3-docs repository and, for PRs, merge the PR head onto the
# target branch.
REPO_LOCATION="${REPO_LOCATION:-${HOME}/tested_repo}"
rm -rf "${REPO_LOCATION}"
git clone "https://github.com/${REPO_ORG}/${REPO_NAME}.git" "${REPO_LOCATION}"
cd "${REPO_LOCATION}"
git checkout "${REPO_BRANCH}"

# If the target and source repos and branches are identical (periodic run),
# don't try to merge.
if [[ "${UPDATED_REPO}" != *"${REPO_ORG}/${REPO_NAME}"* ]] ||
    [[ "${UPDATED_BRANCH}" != "${REPO_BRANCH}" ]]; then
    git config user.email "test@test.test"
    git config user.name "Test"
    git remote add test "${UPDATED_REPO}"
    git fetch test
    if [[ -n "${PR_ID:-}" ]]; then
        git fetch origin "pull/${PR_ID}/head:${UPDATED_BRANCH}-branch" || true
    fi
    # Merging the PR with the target branch
    git merge "${UPDATED_BRANCH}" || exit
fi

echo "Running the Quick Start Guide test"

# Install libvirt
sudo apt-get update
sudo apt-get install -y libvirt-daemon-system qemu-kvm virt-manager libvirt-dev

# Ensure the CI user is in the libvirt group so it can manage VMs.
sudo usermod -a -G libvirt "${USER}"

# We need a new shell to pick up the new libvirt group membership. That is why
# we run the test via "sudo -s -u ${USER}".
sudo -s -u "${USER}" --preserve-env bash "${REPO_LOCATION}/hack/quick-start/quick-start-test.sh"
