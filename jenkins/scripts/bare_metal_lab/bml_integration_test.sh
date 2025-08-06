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
REPO_NAME="${REPO_NAME:-metal3-dev-env}"
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

CAPI_VERSION="${CAPI_VERSION:-v1beta1}"
CAPM3_VERSION="${CAPM3_VERSION:-v1beta1}"
CAPM3RELEASEBRANCH="${CAPM3RELEASEBRANCH:-main}"
BMORELEASEBRANCH="${BMORELEASEBRANCH:-main}"
BARE_METAL_LAB=true

cat <<-EOF >"/tmp/vars.sh"
REPO_ORG="${REPO_ORG}"
REPO_NAME="${REPO_NAME}"
REPO_BRANCH="${REPO_BRANCH}"
UPDATED_REPO="${UPDATED_REPO}"
UPDATED_BRANCH="${UPDATED_BRANCH}"
CAPI_VERSION="${CAPI_VERSION}"
CAPM3_VERSION="${CAPM3_VERSION}"
CAPM3RELEASEBRANCH="${CAPM3RELEASEBRANCH}"
BMORELEASEBRANCH="${BMORELEASEBRANCH}"
IMAGE_OS="${IMAGE_OS}"
TARGET_NODE_MEMORY="${TARGET_NODE_MEMORY}"
BARE_METAL_LAB="${BARE_METAL_LAB}"
export IRONIC_IMAGE="quay.io/metal3-io/ironic:v30.0.0"
EOF

cat "${CI_DIR}/../dynamic_worker_workflow/test_env.sh" >>"/tmp/vars.sh"

echo "Setting up the lab"

ANSIBLE_FORCE_COLOR=true ansible-playbook -v "${CI_DIR}"/deploy-lab.yaml

echo "Running the tests"
# Execute remote script
# shellcheck disable=SC2029

"${CI_DIR}"/run_integration_tests.sh /tmp/vars.sh "${GITHUB_TOKEN}"
