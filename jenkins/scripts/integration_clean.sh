#! /usr/bin/env bash

set -eu

# Description:
# Runs in main integration cleanup job defined in jjb. 
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
  # Fetch VMs which are 6+(21600 seconds) hours old
  VM_LIST=$(openstack server list -f json | jq -r '.[] | select(.Name |
    startswith("ci-test-vm-")) | select((.Name | ltrimstr("ci-test-vm-") |
    split("-") | .[0] | strptime("%Y%m%d%H%M%S") | mktime) < (now - 21600))
    | .ID ')

  # Fetch VMs which are 24+(86400 seconds) hours old
  DEBUGGING_VM_LIST=$(openstack server list -f json | jq -r '.[] | select(.Name |
  startswith("ci-test-keep-vm-")) | select((.Name | ltrimstr("ci-test-keep-vm-") |
  split("-") | .[0] | strptime("%Y%m%d%H%M%S") | mktime) < (now - 86400))
  | .ID ')
  
  FINAL_LIST=$(IFS=$'\n'; echo "${VM_LIST[*]}" "${DEBUGGING_VM_LIST[*]}")

  echo "Cleaning old leftover resources"
  
  for VM_NAME in $FINAL_LIST
  do
    # Delete executer vm
    echo "Deleting executer VM ${VM_NAME}."
    openstack server delete "${VM_NAME}"
    echo "Executer VM ${VM_NAME} is deleted."
  done
  
  # List ports which are 6+(21600 seconds) hours old
  PORT_LIST=$(openstack port list -f json | jq -r '.[] | select(.Name |
    startswith("ci-test-vm-")) | select((.Name | ltrimstr("ci-test-vm-") |
    rtrimstr("-int-port") | split("-") | .[0] | strptime("%Y%m%d%H%M%S") |
    mktime) < (now - 21600)) | .ID ')

# List ports which are 24+(86400 seconds) hours old
  DEBUGGING_VM_PORT_LIST=$(openstack port list -f json | jq -r '.[] | select(.Name |
  startswith("ci-test-keep-vm-")) | select((.Name | ltrimstr("ci-test-keep-vm-") |
  rtrimstr("-int-port") | split("-") | .[0] | strptime("%Y%m%d%H%M%S") |
  mktime) < (now - 86400)) | .ID ')
  
  FINAL_PORT_LIST=$(IFS=$'\n'; echo "${PORT_LIST[*]}" "${DEBUGGING_VM_PORT_LIST[*]}")

  for PORT_NAME in $FINAL_PORT_LIST
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
OS_REGION_NAME="Kna1"
OS_AUTH_URL="https://kna1.citycloud.com:5000"
echo "Running in region: $OS_REGION_NAME"
cleanup
