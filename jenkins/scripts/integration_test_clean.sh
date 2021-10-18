#! /usr/bin/env bash

set -eu

# Description:
# Runs in every single master job and in jobs triggered within the PR in metal3 repos. 
# Consumed by integration_tests.pipeline and cleans the integration test results by
# running 'make clean' target (check run_clean.sh script) eventually.
#   Requires:
#     - source openstack.rc file
# Usage:
#  integration_test_clean.sh
#

CI_DIR="$(dirname "$(readlink -f "${0}")")"

REPO_NAME="${REPO_NAME:-metal3-dev-env}"
DISTRIBUTION="${DISTRIBUTION:-ubuntu}"

# shellcheck disable=SC1090
source "${CI_DIR}/utils.sh"

TEST_EXECUTER_PORT_NAME="${TEST_EXECUTER_PORT_NAME:-${TEST_EXECUTER_VM_NAME}-int-port}"

if [[ "${UPDATED_BRANCH}" =~ "^(main|master)$" ]]
then
  OS_REGION_NAME="Fra1"
  OS_AUTH_URL="https://fra1.citycloud.com:5000"
fi

# Get the IP
TEST_EXECUTER_IP="$(openstack port show -f json "${TEST_EXECUTER_PORT_NAME}" \
  | jq -r '.fixed_ips[0].ip_address')"

if [[ "$OS_REGION_NAME" != "Kna1" ]]
then
  FLOATING_IP="$(openstack floating ip list --fixed-ip-address "${TEST_EXECUTER_IP}" \
    -c "Floating IP Address" -f value)"
  TEST_EXECUTER_IP="${FLOATING_IP}"
fi

# Send Remote script to Executer
scp \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -i "${AIRSHIP_CI_USER_KEY}" \
  "${CI_DIR}/files/run_clean.sh" \
  "${AIRSHIP_CI_USER}@${TEST_EXECUTER_IP}:/tmp/" > /dev/null

echo "Cleaning"
# Execute remote cleaning script
# shellcheck disable=SC2029
ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ServerAliveInterval=15 \
  -i "${AIRSHIP_CI_USER_KEY}" \
  "${AIRSHIP_CI_USER}"@"${TEST_EXECUTER_IP}" \
  PATH=/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:/bin \
  /tmp/run_clean.sh "${REPO_NAME}" "${DISTRIBUTION}"
