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

DISTRIBUTION="${DISTRIBUTION:-ubuntu}"
if [ "${DISTRIBUTION}" == "ubuntu" ]
then
  IMAGE_NAME="${CI_METAL3_IMAGE}"
  IMAGE_OS="Ubuntu"
else
  IMAGE_NAME="${CI_METAL3_CENTOS_IMAGE}"
  IMAGE_OS="Centos"
fi

REPO_ORG="${REPO_ORG:-metal3-io}"
REPO_NAME="${REPO_NAME:-metal3-dev-env}"
REPO_BRANCH="${REPO_BRANCH:-master}"
UPDATED_REPO="${UPDATED_REPO:-https://github.com/${REPO_ORG}/${REPO_NAME}.git}"
UPDATED_BRANCH="${UPDATED_BRANCH:-master}"
CAPI_VERSION="${CAPI_VERSION:-v1alpha3}"
NUM_NODES="${NUM_NODES:-2}"
TESTS_FOR="${TESTS_FOR:-integration_test}"

DEFAULT_HOSTS_MEMORY="8192"

VM_TIMELABEL="${VM_TIMELABEL:-$(date '+%Y%m%d%H%M%S')}"
TEST_EXECUTER_VM_NAME="${TEST_EXECUTER_VM_NAME:-ci-test-vm-${VM_TIMELABEL}}"
TEST_EXECUTER_PORT_NAME="${TEST_EXECUTER_PORT_NAME:-${TEST_EXECUTER_VM_NAME}-int-port}"

if [ "${TESTS_FOR}" == "feature_tests" ]
then
  TEST_EXECUTER_FLAVOR="${TEST_EXECUTER_FLAVOR:-8C-32GB-300GB}"
fi

if [ "${IMAGE_OS}" == "Ubuntu" ]
then
  TEST_EXECUTER_FLAVOR="${TEST_EXECUTER_FLAVOR:-4C-16GB-200GB}"
else
  TEST_EXECUTER_FLAVOR="${TEST_EXECUTER_FLAVOR:-4C-32GB-200GB}"
fi

echo "Creating new executer VM."

# Creating new port, needed to immediately get the ip
EXT_PORT_ID="$(openstack port create -f json \
  --network "${CI_EXT_NET}" \
  --fixed-ip subnet="$(get_subnet_name "${CI_EXT_NET}")" \
  "${TEST_EXECUTER_PORT_NAME}" | jq -r '.id')"

# Create new executer vm
openstack server create -f json \
  --image "${IMAGE_NAME}" \
  --flavor "${TEST_EXECUTER_FLAVOR}" \
  --port "${EXT_PORT_ID}" \
  "${TEST_EXECUTER_VM_NAME}" | jq -r '.id'

# Get the IP
TEST_EXECUTER_IP="$(openstack port show -f json "${TEST_EXECUTER_PORT_NAME}" \
  | jq -r '.fixed_ips[0].ip_address')"

echo "Waiting for the host ${TEST_EXECUTER_VM_NAME} to come up"
#Wait for the host to come up
wait_for_ssh "${AIRSHIP_CI_USER}" "${AIRSHIP_CI_USER_KEY}" "${TEST_EXECUTER_IP}"

# Send Remote script to Executer
scp \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -i "${AIRSHIP_CI_USER_KEY}" \
  "${CI_DIR}/files/run_integration_tests.sh" \
  "${AIRSHIP_CI_USER}@${TEST_EXECUTER_IP}:/tmp/" > /dev/null

echo "Running the tests"
# Execute remote script
# shellcheck disable=SC2029
ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ServerAliveInterval=15 \
  -i "${AIRSHIP_CI_USER_KEY}" \
  "${AIRSHIP_CI_USER}"@"${TEST_EXECUTER_IP}" \
  PATH=/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:/bin \
  /tmp/run_integration_tests.sh "${REPO_ORG}" "${REPO_NAME}" "${REPO_BRANCH}" \
  "${UPDATED_REPO}" "${UPDATED_BRANCH}" "${CAPI_VERSION}" "${IMAGE_OS}" \
  "${DEFAULT_HOSTS_MEMORY}" "${DISTRIBUTION}" "${GITHUB_TOKEN}" "${NUM_NODES}" \
  "${TESTS_FOR}"
