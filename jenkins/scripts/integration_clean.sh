#! /usr/bin/env bash

set -eu

# Description:
# Runs in master integration cleanup job defined in jjb. 
# Consumed by integration_tests_clean.pipeline and cleans any leftover executer vm
# and port once every day.
#   Requires:
#     - source openstack.rc file
# Usage:
#  integration_clean.sh
#

CI_DIR="$(dirname "$(readlink -f "${0}")")"

# shellcheck disable=SC1090
source "${CI_DIR}/utils.sh"

function cleanup() {
  VM_LIST=$(openstack server list -f json | jq -r '.[] | select(.Name |
    startswith("ci-test-vm-")) | select((.Name | ltrimstr("ci-test-vm-") |
    split("-") | .[0] | strptime("%Y%m%d%H%M%S") | mktime) < (now - 21600))
    | .ID ')
  
  echo "Cleaning old leftover resources"
  
  for VM_NAME in $VM_LIST
  do
    # Delete executer vm
    echo "Deleting executer VM ${VM_NAME}."
    openstack server delete "${VM_NAME}"
    echo "Executer VM ${VM_NAME} is deleted."
  done
  
  PORT_LIST=$(openstack port list -f json | jq -r '.[] | select(.Name |
    startswith("ci-test-vm-")) | select((.Name | ltrimstr("ci-test-vm-") |
    rtrimstr("-int-port") | split("-") | .[0] | strptime("%Y%m%d%H%M%S") |
    mktime) < (now - 21600)) | .ID ')
  
  for PORT_NAME in $PORT_LIST
  do
    # Delete executer vm port
    echo "Deleting executer VM port ${PORT_NAME}."
    openstack port delete "${PORT_NAME}"
    echo "Executer VM port ${PORT_NAME} is deleted."
  done
  
  echo "Old leftover resources are cleaned successfully!"
}


# Run in default region
echo "Running in region: $OS_REGION_NAME"
cleanup

# Run in Frankfurt region
OS_REGION_NAME="Fra1"
OS_AUTH_URL="https://fra1.citycloud.com:5000"
echo "Running in region: $OS_REGION_NAME"
cleanup
