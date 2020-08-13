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
CAPI_VERSION="${CAPI_VERSION:-v1alpha3}"
CAPM3_VERSION="${CAPM3_VERSION:-v1alpha3}"
IMAGE_OS="${IMAGE_OS:-Ubuntu}"
DEFAULT_HOSTS_MEMORY="${DEFAULT_HOSTS_MEMORY:-4096}"
DISTRIBUTION="${DISTRIBUTION:-ubuntu}"
NUM_NODES="${NUM_NODES:-2}"
TESTS_FOR="${TESTS_FOR:-integration_test}"

VM_TIMELABEL="${VM_TIMELABEL:-$(date '+%Y%m%d%H%M%S')}"
TEST_EXECUTER_VM_NAME="${TEST_EXECUTER_VM_NAME:-ci-test-vm-${VM_TIMELABEL}}"
TEST_EXECUTER_PORT_NAME="${TEST_EXECUTER_PORT_NAME:-${TEST_EXECUTER_VM_NAME}-int-port}"

if [[ "${TESTS_FOR}" == "feature_tests"* ]]
then
  TEST_EXECUTER_FLAVOR="${TEST_EXECUTER_FLAVOR:-8C-32GB-300GB}"
fi

TEST_EXECUTER_FLAVOR="${TEST_EXECUTER_FLAVOR:-4C-16GB-200GB}"

DISTRIBUTION="${DISTRIBUTION:-ubuntu}"
if [ "${DISTRIBUTION}" == "ubuntu" ]
then
  IMAGE_NAME="${CI_METAL3_IMAGE}"
  BASE_VOLUME_NAME="metal3-ubuntu"
  sh "${CI_DIR}/integration_test_setup.sh"
else
  IMAGE_NAME="${CI_METAL3_CENTOS_IMAGE}"
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
  echo "Getting the IP address of a test executer VM."
  TEST_EXECUTER_IP="$(openstack port show -f json "${TEST_EXECUTER_PORT_NAME}" \
    | jq -r '.fixed_ips[0].ip_address')"


  echo "Waiting for the host ${TEST_EXECUTER_VM_NAME} to come up"
  #Wait for the host to come up
  wait_for_ssh "${AIRSHIP_CI_USER}" "${AIRSHIP_CI_USER_KEY}" "${TEST_EXECUTER_IP}"
fi

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
EOF

# Send Remote script to Executer
echo "Copying run_integration_tests.sh script to test executer VM."
scp \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -i "${AIRSHIP_CI_USER_KEY}" \
  "${CI_DIR}/files/run_integration_tests.sh" \
  "${CI_DIR}/files/vars.sh" \
  "${AIRSHIP_CI_USER}@${TEST_EXECUTER_IP}:/tmp/" > /dev/null

# Execute remote script
# shellcheck disable=SC2029
echo "Running the tests."
ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=10 \
  -i "${AIRSHIP_CI_USER_KEY}" \
  "${AIRSHIP_CI_USER}"@"${TEST_EXECUTER_IP}" \
  PATH=/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:/bin \
  /tmp/run_integration_tests.sh /tmp/vars.sh "${GITHUB_TOKEN}"