#!/usr/bin/env bash

set -xeu

# Description:
#   Runs the integration tests for metal3-dev-env in the BML
#   Requires:
#     - jumphost (TEST_EXECUTER_IP) up and running and accessible
#     - environment variables set:
#       - METAL3_CI_USER: Ci user for jumphost.
#       - METAL3_CI_USER_KEY: Path of the CI user private key for jumphost.
#       - GITHUB_TOKEN: Token for interatcion with Github API (e.g. get releases)
# Usage:
#  bml_integration_test.sh
#

CI_DIR="$(dirname "$(readlink -f "${0}")")"

REPO_ORG="${REPO_ORG:-metal3-io}"
REPO_NAME="${REPO_NAME:-project-infra}"
REPO_BRANCH="${REPO_BRANCH:-main}"
UPDATED_REPO="${UPDATED_REPO:-https://github.com/${REPO_ORG}/${REPO_NAME}.git}"
UPDATED_BRANCH="${UPDATED_BRANCH:-main}"
PR_ID="${PR_ID:-}"

if [[ "${REPO_NAME}" == "metal3-dev-env" ]]; then
    export BML_METAL3_DEV_ENV_REPO="${UPDATED_REPO}"
    export BML_METAL3_DEV_ENV_BRANCH="${UPDATED_BRANCH}"
else
    export BML_METAL3_DEV_ENV_REPO="https://github.com/metal3-io/metal3-dev-env.git"
    export BML_METAL3_DEV_ENV_BRANCH="main"
fi

# See bare metal lab infrastructure documentation:
# https://wiki.nordix.org/pages/viewpage.action?spaceKey=CPI&title=Bare+Metal+Lab
# In the bare metal lab, the external network has vlan id 3
export EXTERNAL_VLAN_ID="${EXTERNAL_VLAN_ID:-"3"}"

export EPHEMERAL_CLUSTER="${EPHEMERAL_CLUSTER:-"minikube"}"
export CAPI_VERSION="${CAPI_VERSION:-v1beta2}"
export CAPM3_VERSION="${CAPM3_VERSION:-v1beta1}"
export CAPM3RELEASEBRANCH="${CAPM3RELEASEBRANCH:-main}"
export BMORELEASEBRANCH="${BMORELEASEBRANCH:-main}"
export IMAGE_OS="${IMAGE_OS:-centos}"
export GITHUB_TOKEN="${GITHUB_TOKEN:-}"
export FORCE_REPO_UPDATE=false
export NUM_NODES="${NUM_NODES:-"2"}"
export CONTROL_PLANE_MACHINE_COUNT="${CONTROL_PLANE_MACHINE_COUNT:-"1"}"
export WORKER_MACHINE_COUNT="${WORKER_MACHINE_COUNT:-"1"}"


# shellcheck disable=SC1091
. "${CI_DIR}/../dynamic_worker_workflow/test_env.sh"

echo "Setting up the lab"
ANSIBLE_FORCE_COLOR=true ansible-playbook -v "${CI_DIR}"/deploy-lab.yaml

# In the bare metal lab, we have already cloned metal3-dev-env and we run integration tests
# so no need to clone other repos.
if [[ "${REPO_NAME}" == "metal3-dev-env" ]]; then
    cd "${HOME}/tested_repo"
else
    cd "${HOME}/metal3"
fi

echo "Running the tests"

make test
