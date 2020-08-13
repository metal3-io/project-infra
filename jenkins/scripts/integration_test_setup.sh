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

# Create new port, needed to immediately get the ip
echo "Creating a new port to get an IP address."
EXT_PORT_ID="$(openstack port create -f json \
  --network "${CI_EXT_NET}" \
  --fixed-ip subnet="$(get_subnet_name "${CI_EXT_NET}")" \
  "${TEST_EXECUTER_PORT_NAME}" | jq -r '.id')"

# Get the base volume
echo "Getting the base volume."
BASE_VOLUME_NAME_ID="$(openstack volume show -f json \
  "${BASE_VOLUME_NAME}" | jq -r '.id')"

# Create test executer volume from copy of base volume
echo "Creating a test executer volume from copy of base volume."
TEST_EXECUTER_VOLUME_ID="$(openstack volume create -f json \
  --source "${BASE_VOLUME_NAME_ID}" \
  --size 200 \
  "${TEST_EXECUTER_VM_NAME}" | jq -r '.id')"

# Wait for a test executer volume to be available...
echo "Waiting for a test executer volume to be available."
until openstack volume show "${TEST_EXECUTER_VM_NAME}" -f json \
  | jq .status | grep "available"
do
  sleep 10
done

# Create a test executer VM from copy of the test executer volume
echo "Creating a test executer VM from the test executer volume."
openstack server create \
  --volume "${TEST_EXECUTER_VOLUME_ID}" \
  --flavor "${TEST_EXECUTER_FLAVOR}" \
  --port "${EXT_PORT_ID}" \
  "${TEST_EXECUTER_VM_NAME}"

# Get the IP
echo "Getting the IP address of a test executer VM."
TEST_EXECUTER_IP="$(openstack port show -f json "${TEST_EXECUTER_PORT_NAME}" \
  | jq -r '.fixed_ips[0].ip_address')"

# Wait for the host to come up
echo "Waiting for the host ${TEST_EXECUTER_VM_NAME} to come up."
wait_for_ssh "${AIRSHIP_CI_USER}" "${AIRSHIP_CI_USER_KEY}" "${TEST_EXECUTER_IP}"
