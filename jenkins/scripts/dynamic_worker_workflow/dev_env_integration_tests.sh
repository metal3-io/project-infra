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
export METAL3REPO="${METAL3REPO:-https://github.com/metal3-io/metal3-dev-env.git}"
export METAL3BRANCH="${METAL3BRANCH:-main}"
export CAPM3RELEASEBRANCH="${CAPM3RELEASEBRANCH:-main}"
export BMORELEASEBRANCH="${BMORELEASEBRANCH:-main}"
export NUM_NODES="${NUM_NODES:-1}"
export TARGET_NODE_MEMORY="${TARGET_NODE_MEMORY:-4096}"
export IRONIC_INSTALL_TYPE="${IRONIC_INSTALL_TYPE:-rpm}"
export IRONIC_FROM_SOURCE="${IRONIC_FROM_SOURCE:-false}"
export BUILD_IRONIC_IMAGE_LOCALLY=""

if [[ "${IRONIC_INSTALL_TYPE}" == "source" ]]; then
    IRONIC_FROM_SOURCE="true"
    if [[ "${REPO_NAME}" == "ironic-image" ]]; then
        export IRONIC_LOCAL_IMAGE="/home/${USER}/tested_repo"
    else
        BUILD_IRONIC_IMAGE_LOCALLY="true"
    fi
fi

# shellcheck disable=SC1091
. "${CI_DIR}/integration_test_env.sh"

# Run:
#   - ansible, basic integration
export FORCE_REPO_UPDATE=false

if [[ "${IMAGE_OS}" == "ubuntu" ]]; then
    #Must match with run_fetch_logs.sh
    export CONTAINER_RUNTIME="docker"
    export EPHEMERAL_CLUSTER="kind"
else
    export EPHEMERAL_CLUSTER="minikube"
fi

git clone "https://github.com/${REPO_ORG}/${REPO_NAME}.git" tested_repo
cd tested_repo
git checkout "${REPO_BRANCH}"
cd ../

if [[ "${REPO_NAME}" == "metal3-dev-env" ]]; then
    # it will already be cloned to tested_repo
    pushd tested_repo
else
    # clone metal3-dev-env and run the test from there
    git clone "${METAL3REPO}" metal3
    pushd metal3
    git checkout "${METAL3BRANCH}"
fi

echo "Running the tests"

make
make test
