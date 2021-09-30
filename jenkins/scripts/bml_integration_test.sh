#! /usr/bin/env bash

set -eu

# Description:
#   Runs the integration tests for metal3-dev-env in an executer vm
#   Requires:
#     - source stackrc file
#     - openstack ci infra should already be deployed.
#     - environment variables set:
#       - AIRSHIP_CI_USER: Ci user for jumphost.
#       - AIRSHIP_CI_USER_KEY: Path of the CI user private key for jumphost.
# Usage:
#  integration_test.sh
#

CI_DIR="$(dirname "$(readlink -f "${0}")")"

# shellcheck disable=SC1090
source "${CI_DIR}/utils.sh"

REPO_ORG="${REPO_ORG:-metal3-io}"
REPO_NAME="${REPO_NAME:-metal3-dev-env}"
REPO_BRANCH="${REPO_BRANCH:-master}"
UPDATED_REPO="${UPDATED_REPO:-https://github.com/${REPO_ORG}/${REPO_NAME}.git}"
UPDATED_BRANCH="${UPDATED_BRANCH:-master}"
CAPI_VERSION="${CAPI_VERSION:-v1alpha4}"
CAPM3_VERSION="${CAPM3_VERSION:-v1alpha5}"
NUM_NODES="${NUM_NODES:-2}"
TESTS_FOR="${TESTS_FOR:-integration_test}"
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
IMAGE_OS="${IMAGE_OS}"
DEFAULT_HOSTS_MEMORY="${DEFAULT_HOSTS_MEMORY}"
DISTRIBUTION="${DISTRIBUTION}"
NUM_NODES="${NUM_NODES}"
TESTS_FOR="${TESTS_FOR}"
BARE_METAL_LAB="${BARE_METAL_LAB}"
EOF

# Send Remote script to Executer
scp \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -i "${AIRSHIP_CI_USER_KEY}" \
  -r \
  "${CI_DIR}/files/run_integration_tests.sh" \
  "${CI_DIR}/files/vars.sh" \
  "${CI_DIR}/bare_metal_lab/" \
  "${AIRSHIP_CI_USER}@${TEST_EXECUTER_IP}:/tmp/" > /dev/null

echo "Setting up the lab"
# Execute remote script
# shellcheck disable=SC2029
ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=10 \
  -i "${AIRSHIP_CI_USER_KEY}" \
  "${AIRSHIP_CI_USER}"@"${TEST_EXECUTER_IP}" \
  -o SendEnv="MYVAR" \
  -o SendEnv="MYVAR" \
  ansible-playbook /tmp/bare_metal_lab/deploy-lab.yaml

echo "Running the tests"
# Execute remote script
# shellcheck disable=SC2029
ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=10 \
  -i "${AIRSHIP_CI_USER_KEY}" \
  "${AIRSHIP_CI_USER}"@"${TEST_EXECUTER_IP}" \
  PATH=/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:/bin \
  /tmp/run_integration_tests.sh /tmp/vars.sh "${GITHUB_TOKEN}"
