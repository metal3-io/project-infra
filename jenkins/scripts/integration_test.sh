#! /usr/bin/env bash

set -eu

# Description:
#   Runs the integration tests for metal3-dev-env in an executer vm
#   Requires:
#     - source stackrc file
#     - openstack ci infra should already be deployed.
#     - environment variables set:
#       - METAL3_CI_USER: Ci user for jumphost.
#       - METAL3_CI_USER_KEY: Path of the CI user private key for jumphost.
# Usage:
#  integration_test.sh
#

CI_DIR="$(dirname "$(readlink -f "${0}")")"

# shellcheck disable=SC1090
source "${CI_DIR}/utils.sh"

IMAGE_OS="${IMAGE_OS:-ubuntu}"
if [ "${IMAGE_OS}" == "ubuntu" ]
then
  IMAGE_NAME="${CI_METAL3_IMAGE}"
else
  IMAGE_NAME="${CI_METAL3_CENTOS_IMAGE}"
fi

REPO_ORG="${REPO_ORG:-metal3-io}"
REPO_NAME="${REPO_NAME:-metal3-dev-env}"
REPO_BRANCH="${REPO_BRANCH}"
UPDATED_REPO="${UPDATED_REPO:-https://github.com/${REPO_ORG}/${REPO_NAME}.git}"
UPDATED_BRANCH="${UPDATED_BRANCH:-main}"
CAPI_VERSION="${CAPI_VERSION:-v1beta1}"
CAPM3_VERSION="${CAPM3_VERSION:-v1beta1}"
NUM_NODES="${NUM_NODES:-2}"
TESTS_FOR="${TESTS_FOR:-integration_test}"
BARE_METAL_LAB=false
DEFAULT_HOSTS_MEMORY="${DEFAULT_HOSTS_MEMORY:-4096}"
UPGRADE_TEST="${UPGRADE_TEST:-false}"
TEST_EXECUTER_VM_NAME="${TEST_EXECUTER_VM_NAME}"
TEST_EXECUTER_PORT_NAME="${TEST_EXECUTER_PORT_NAME:-${TEST_EXECUTER_VM_NAME}-int-port}"
TEST_EXECUTER_FIP_TAG="${TEST_EXECUTER_FIP_TAG:-${TEST_EXECUTER_VM_NAME}-floating-ip}"

# Run feature tests, e2e tests, main and release* tests in the Frankfurt region
if [[ "${TESTS_FOR}" == "feature_tests"* ]] || [[ "${TESTS_FOR}" == "e2e_tests"* ]] || \
   [[ "${UPDATED_BRANCH}" == "main" ]] || [[ "${UPDATED_BRANCH}" == "release"* ]]
then
  OS_REGION_NAME="Fra1"
  OS_AUTH_URL="https://fra1.citycloud.com:5000"
fi
echo "Running in region: $OS_REGION_NAME"

if [[ "${TESTS_FOR}" == "feature_tests"* || "${TESTS_FOR}" == "e2e_tests"* ]]
then
    # Four node cluster
    TEST_EXECUTER_FLAVOR="${TEST_EXECUTER_FLAVOR:-8C-32GB-300GB}"
else
    # Two node cluster
    TEST_EXECUTER_FLAVOR="${TEST_EXECUTER_FLAVOR:-4C-16GB-100GB}"
fi

# Creating new port, needed to immediately get the ip
EXT_PORT_ID="$(openstack port create -f json \
  --network "${CI_EXT_NET}" \
  --fixed-ip subnet="$(get_subnet_name "${CI_EXT_NET}")" \
  "${TEST_EXECUTER_PORT_NAME}" | jq -r '.id')"

# Create new executer vm
echo "Creating server ${TEST_EXECUTER_VM_NAME}"
openstack server create -f json \
  --image "${IMAGE_NAME}" \
  --flavor "${TEST_EXECUTER_FLAVOR}" \
  --port "${EXT_PORT_ID}" \
  "${TEST_EXECUTER_VM_NAME}" | jq -r '.id'

# Get the IP
TEST_EXECUTER_IP="$(openstack port show -f json "${TEST_EXECUTER_PORT_NAME}" \
  | jq -r '.fixed_ips[0].ip_address')"

if [[ "$OS_REGION_NAME" != "Kna1" ]]
then
  # Create floating IP
  FLOATING_IP="$(openstack floating ip create -f value -c name \
    --tag "${TEST_EXECUTER_FIP_TAG}" \
    "${CI_FLOATING_IP_NET}")"

  if [[ -z "$FLOATING_IP" ]]
  then
    echo "No floating IP is available"
    exit 1
  fi
  TEST_EXECUTER_IP="$FLOATING_IP"

  # Attach floating IP
  openstack server add floating ip \
  "${TEST_EXECUTER_VM_NAME}" \
  "$FLOATING_IP"
fi

for i in {1..6}; do
  echo "Waiting for the host ${TEST_EXECUTER_VM_NAME} to come up"
  # Wait for the host to come up
  wait_for_ssh "${METAL3_CI_USER}" "${METAL3_CI_USER_KEY}" "${TEST_EXECUTER_IP}"
  if vm_healthy "${METAL3_CI_USER}" "${METAL3_CI_USER_KEY}" "${TEST_EXECUTER_IP}"; then
    break
  else
    if [ ${i} -eq 5 ]; then
      echo "Server is still unhealthy after retry. Giving up."
      exit 1
    fi
    echo "Trying to create server again. Retry ${i}/5"
    echo "Deleting unhealthy server ${TEST_EXECUTER_VM_NAME}..."
    openstack server delete "${TEST_EXECUTER_VM_NAME}"
    echo "Server ${TEST_EXECUTER_VM_NAME} deleted."

    # Create new executer vm
    echo "Recreating server ${TEST_EXECUTER_VM_NAME}"
    openstack server create -f json \
      --image "${IMAGE_NAME}" \
      --flavor "${TEST_EXECUTER_FLAVOR}" \
      --port "${EXT_PORT_ID}" \
      "${TEST_EXECUTER_VM_NAME}" | jq -r '.id'

    if [[ "$OS_REGION_NAME" != "Kna1" ]]
    then
      # Attach floating IP
      openstack server add floating ip \
        "${TEST_EXECUTER_VM_NAME}" \
        "$FLOATING_IP"
    fi
  fi
done

cat <<-EOF >> "${CI_DIR}/files/vars.sh"
REPO_ORG="${REPO_ORG}"
REPO_NAME="${REPO_NAME}"
REPO_BRANCH="${REPO_BRANCH}"
UPDATED_REPO="${UPDATED_REPO}"
UPDATED_BRANCH="${UPDATED_BRANCH}"
CAPI_VERSION="${CAPI_VERSION}"
CAPM3_VERSION="${CAPM3_VERSION}"
IMAGE_OS="${IMAGE_OS}"
DEFAULT_HOSTS_MEMORY="${DEFAULT_HOSTS_MEMORY}"
NUM_NODES="${NUM_NODES}"
TESTS_FOR="${TESTS_FOR}"
BARE_METAL_LAB="${BARE_METAL_LAB}"
UPGRADE_TEST="${UPGRADE_TEST}"
EOF

# Only set these variables if they actually have values.
# If the variable is unset or empty (""), do nothing.
if [[ ! -z "${CAPIRELEASE:+x}" ]]
then
  echo "CAPIRELEASE=${CAPIRELEASE}" | tee --append "${CI_DIR}/files/vars.sh"
fi
if [[ ! -z "${CAPM3RELEASE:+x}" ]]
then
  echo "CAPM3RELEASE=${CAPM3RELEASE}" | tee --append "${CI_DIR}/files/vars.sh"
fi


cat "${CI_DIR}/integration_test_env.sh" >> "${CI_DIR}/files/vars.sh"

# Send Remote script to Executer
scp \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -i "${METAL3_CI_USER_KEY}" \
  "${CI_DIR}/files/run_integration_tests.sh" \
  "${CI_DIR}/files/vars.sh" \
  "${METAL3_CI_USER}@${TEST_EXECUTER_IP}:/tmp/" > /dev/null

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
