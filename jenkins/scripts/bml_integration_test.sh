#! /usr/bin/env bash

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

# shellcheck disable=SC1090
source "${CI_DIR}/utils.sh"

REPO_ORG="${REPO_ORG:-metal3-io}"
REPO_NAME="${REPO_NAME:-metal3-dev-env}"
REPO_BRANCH="${REPO_BRANCH:-main}"
UPDATED_REPO="${UPDATED_REPO:-https://github.com/${REPO_ORG}/${REPO_NAME}.git}"
UPDATED_BRANCH="${UPDATED_BRANCH:-main}"
if [[ "${REPO_NAME}" == "metal3-dev-env" ]]; then
  export BML_METAL3_DEV_ENV_REPO="${UPDATED_REPO}"
  export BML_METAL3_DEV_ENV_BRANCH="${UPDATED_BRANCH}"
else
  # export BML_METAL3_DEV_ENV_REPO="https://github.com/metal3-io/metal3-dev-env.git"
  # export BML_METAL3_DEV_ENV_BRANCH="main"
  export BML_METAL3_DEV_ENV_REPO="https://github.com/Nordix/metal3-dev-env.git"
  export BML_METAL3_DEV_ENV_BRANCH="increase-calico-timeout/sunnat"
fi

CAPI_VERSION="${CAPI_VERSION:-v1beta1}"
CAPM3_VERSION="${CAPM3_VERSION:-v1beta1}"
CAPM3RELEASEBRANCH="${CAPM3RELEASEBRANCH:-main}"
NUM_NODES="${NUM_NODES:-2}"
TESTS_FOR="${TESTS_FOR:-integration_test}"
GINKGO_FOCUS="${GINKGO_FOCUS:-}"
EPHEMERAL_TEST="${EPHEMERAL_TEST:-false}"
BARE_METAL_LAB=true

TEST_EXECUTER_IP="129.192.80.20"

cat <<-EOF > "${CI_DIR}/files/vars.sh"
REPO_ORG="${REPO_ORG}"
REPO_NAME="${REPO_NAME}"
REPO_BRANCH="${REPO_BRANCH}"
UPDATED_REPO="${UPDATED_REPO}"
UPDATED_BRANCH="${UPDATED_BRANCH}"
CAPI_VERSION="${CAPI_VERSION}"
CAPM3_VERSION="${CAPM3_VERSION}"
CAPM3RELEASEBRANCH="${CAPM3RELEASEBRANCH}"
IMAGE_OS="${IMAGE_OS}"
DEFAULT_HOSTS_MEMORY="${DEFAULT_HOSTS_MEMORY}"
NUM_NODES="${NUM_NODES}"
TESTS_FOR="${TESTS_FOR}"
GINKGO_FOCUS="${GINKGO_FOCUS}"
EPHEMERAL_TEST="${EPHEMERAL_TEST}"
BARE_METAL_LAB="${BARE_METAL_LAB}"
EOF

cat "${CI_DIR}/integration_test_env.sh" >> "${CI_DIR}/files/vars.sh"

# Send Remote script to Executer
scp \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -i "${METAL3_CI_USER_KEY}" \
  -r \
  "${CI_DIR}/files/run_integration_tests.sh" \
  "${CI_DIR}/files/vars.sh" \
  "${CI_DIR}/bare_metal_lab/" \
  "${METAL3_CI_USER}@${TEST_EXECUTER_IP}:/tmp/" > /dev/null

echo "Setting up the lab"
# Execute remote script
# shellcheck disable=SC2029
ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=10 \
  -i "${METAL3_CI_USER_KEY}" \
  "${METAL3_CI_USER}"@"${TEST_EXECUTER_IP}" \
  -o SendEnv="BML_ILO_USERNAME" \
  -o SendEnv="BML_ILO_PASSWORD" \
  -o SendEnv="GITHUB_TOKEN" \
  -o SendEnv="REPO_NAME" \
  -o SendEnv="BML_METAL3_DEV_ENV_REPO" \
  -o SendEnv="BML_METAL3_DEV_ENV_BRANCH" \
  ANSIBLE_FORCE_COLOR=true ansible-playbook -v /tmp/bare_metal_lab/deploy-lab.yaml

echo "Running the tests"
# Execute remote script
# shellcheck disable=SC2029
ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=10 \
  -i "${METAL3_CI_USER_KEY}" \
  "${METAL3_CI_USER}"@"${TEST_EXECUTER_IP}" \
  PATH=/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:/bin \
  /tmp/run_integration_tests.sh /tmp/vars.sh "${GITHUB_TOKEN}"
