#!/usr/bin/env bash

set -eu

# Description:
#   Runs the feature tests in dynamic jenkins worker
# Usage:
#  ./dev_env_integration_tests.sh

CI_DIR="$(dirname "$(readlink -f "${0}")")"

export IMAGE_OS="${IMAGE_OS:-ubuntu}"
export REPO_ORG="${REPO_ORG:-metal3-io}"
export REPO_NAME="${REPO_NAME:-metal3-dev-env}"
export REPO_BRANCH="${REPO_BRANCH:-main}"
export PR_ID="${PR_ID:-}"
export PULL_PULL_SHA="${PULL_PULL_SHA:-}"
export METAL3REPO="${METAL3REPO:-https://github.com/metal3-io/metal3-dev-env.git}"
export METAL3BRANCH="${METAL3BRANCH:-main}"
export CAPM3RELEASEBRANCH="${CAPM3RELEASEBRANCH:-main}"
export BMORELEASEBRANCH="${BMORELEASEBRANCH:-main}"
export NUM_NODES="${NUM_NODES:-1}"
export TARGET_NODE_MEMORY="${TARGET_NODE_MEMORY:-4096}"
export IRONIC_INSTALL_TYPE="${IRONIC_INSTALL_TYPE:-rpm}"
export IRONIC_FROM_SOURCE="${IRONIC_FROM_SOURCE:-false}"
export BUILD_IRONIC_IMAGE_LOCALLY=""
export USE_IRSO="${USE_IRSO:-false}"

if [[ "${IRONIC_INSTALL_TYPE}" == "source" ]]; then
    IRONIC_FROM_SOURCE="true"
    if [[ "${REPO_NAME}" == "ironic-image" ]]; then
        export IRONIC_LOCAL_IMAGE="${HOME}/tested_repo"
    else
        BUILD_IRONIC_IMAGE_LOCALLY="true"
    fi
fi

# shellcheck disable=SC1091
. "${CI_DIR}/test_env.sh"

# Run:
#   - ansible, basic integration
export FORCE_REPO_UPDATE=false

if [[ "${IMAGE_OS}" == "ubuntu" ]]; then
    #Must match with fetch_logs.sh
    export CONTAINER_RUNTIME="docker"
    export BOOTSTRAP_CLUSTER="kind"
else
    export BOOTSTRAP_CLUSTER="minikube"
fi

# Clone the source repository
REPO_LOCATION=${REPO_LOCATION:-"${HOME}/tested_repo"}
rm -rf "${REPO_LOCATION}"
git clone "https://github.com/${REPO_ORG}/${REPO_NAME}.git" "${REPO_LOCATION}"
cd "${REPO_LOCATION}"
git checkout "${REPO_BRANCH}"
# If the target and source repos and branches are identical, don't try to merge
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
cd "${HOME}"

if [[ "${REPO_NAME}" == "metal3-dev-env" ]]; then
    # it will already be cloned to tested_repo
    pushd "${REPO_LOCATION}"
else
    # clone metal3-dev-env and run the test from there
    git clone "${METAL3REPO}" "${HOME}/metal3"
    pushd "${HOME}/metal3"
    git checkout "${METAL3BRANCH}"
fi

echo "Running the tests"

cleanup() {
    if [[ "${CLEANUP_AFTERWARDS:-}" == "true" ]]; then
        echo "Cleaning up the environment"
        make clean
    fi
}
trap cleanup EXIT

make
make test
