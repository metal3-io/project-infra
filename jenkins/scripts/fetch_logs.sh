#! /usr/bin/env bash

set -eu

# Description:
#   Cleans the executer vm after integration tests
#   Requires:
#     - source stackrc file
# Usage:
#  integration_delete.sh
#
BARE_METAL_LAB="${BARE_METAL_LAB:-false}"

CI_DIR="$(dirname "$(readlink -f "${0}")")"
DISTRIBUTION="${DISTRIBUTION:-ubuntu}"
BUILD_TAG="${BUILD_TAG:-logs_integration_tests}"

# shellcheck disable=SC1090
source "${CI_DIR}/utils.sh"

TEST_EXECUTER_PORT_NAME="${TEST_EXECUTER_PORT_NAME:-${TEST_EXECUTER_VM_NAME}-int-port}"

# Run feature tests, e2e tests, main, master and release* tests in the Frankfurt region
if [[ "${TESTS_FOR}" == "feature_tests"* ]] || [[ "${TESTS_FOR}" == "e2e_tests"* ]] || \
   [[ "${UPDATED_BRANCH}" == "main" ]] || [[ "${UPDATED_BRANCH}" == "master" ]] || [[ "${UPDATED_BRANCH}" == "release"* ]]
then
  OS_REGION_NAME="Fra1"
  OS_AUTH_URL="https://fra1.citycloud.com:5000"
fi
if [[ "${BARE_METAL_LAB}" != "true" ]] 
then
  echo "Running in region: $OS_REGION_NAME"
fi

# Get the IP
if [ "${BARE_METAL_LAB}" == true ]; then
  TEST_EXECUTER_IP="129.192.80.20"
else
  TEST_EXECUTER_IP="$(openstack port show -f json "${TEST_EXECUTER_PORT_NAME}" \
  | jq -r '.fixed_ips[0].ip_address')"
  if [[ "$OS_REGION_NAME" != "Kna1" ]]
  then
    FLOATING_IP="$(openstack floating ip list --fixed-ip-address "${TEST_EXECUTER_IP}" \
      -c "Floating IP Address" -f value)"
    TEST_EXECUTER_IP="${FLOATING_IP}"
  fi
fi

# Send Remote script to Executer
scp \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -i "${AIRSHIP_CI_USER_KEY}" \
  "${CI_DIR}/files/run_fetch_logs.sh" \
  "${AIRSHIP_CI_USER}@${TEST_EXECUTER_IP}:/tmp/" > /dev/null

echo "Fetching logs"
# Execute remote script
# shellcheck disable=SC2029
ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ServerAliveInterval=15 \
  -i "${AIRSHIP_CI_USER_KEY}" \
  "${AIRSHIP_CI_USER}"@"${TEST_EXECUTER_IP}" \
  PATH=/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:/bin \
  /tmp/run_fetch_logs.sh "logs-${BUILD_TAG}.tgz" \
  "logs-${BUILD_TAG}" "${DISTRIBUTION}" "${TESTS_FOR}"

# fetch logs tarball
scp \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -i "${AIRSHIP_CI_USER_KEY}" \
  "${AIRSHIP_CI_USER}@${TEST_EXECUTER_IP}:logs-${BUILD_TAG}.tgz" \
  "./" > /dev/null
