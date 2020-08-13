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

VM_LIST=$(openstack server list -f json | jq -r '.[] | select(.Name |
  startswith("ci-test-vm-")) | select((.Name | ltrimstr("ci-test-vm-") |
  split("-") | .[0] | strptime("%Y%m%d%H%M%S") | mktime) < (now - 21600))
  | .ID ')

echo "Cleaning old resources"

for VM_NAME in $VM_LIST
do
  # Delete executer VM
  echo "Deleting executer VM ${VM_NAME}."
  openstack server delete "${VM_NAME}"
done

VOLUME_LIST=$(openstack volume list -f json | jq -r '.[] | select(.Name |
  startswith("ci-test-volume-")) | select((.Name | ltrimstr("ci-test-volume-") |
  split("-") | .[0] | strptime("%Y%m%d%H%M%S") | mktime) < (now - 21600))
  | .ID ')

for VOLUME_NAME in $VOLUME_LIST
do
  # Delete executer volume
  echo "Deleting executer volume ${VOLUME_NAME}."
  openstack volume delete --force "${VOLUME_NAME}"
done

PORT_LIST=$(openstack port list -f json | jq -r '.[] | select(.Name |
  startswith("ci-test-vm-")) | select((.Name | ltrimstr("ci-test-vm-") |
  rtrimstr("-int-port") | split("-") | .[0] | strptime("%Y%m%d%H%M%S") |
  mktime) < (now - 21600)) | .ID ')

for PORT_NAME in $PORT_LIST
do
  # Delete executer VM port
  echo "Deleting executer VM port ${PORT_NAME}."
  openstack port delete "${PORT_NAME}"
done

echo "Old resources cleaned"