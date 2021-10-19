#! /usr/bin/env bash

set -eu

# Description:
# Runs in every single master job and in jobs triggered within the PR in metal3 repos. 
# Consumed by integration_tests.pipeline and cleans the executer vm/volume and port after
# integration tests.
#   Requires:
#     - source openstack.rc file
# Usage:
#  integration_delete.sh
#

CI_DIR="$(dirname "$(readlink -f "${0}")")"

# shellcheck disable=SC1090
source "${CI_DIR}/utils.sh"

TEST_EXECUTER_PORT_NAME="${TEST_EXECUTER_PORT_NAME:-${TEST_EXECUTER_VM_NAME}-int-port}"

# Run feature tests and main and master integration tests in the Frankfurt region
if [[ "${TESTS_FOR}" == "feature_tests"* ]] || \
   [[ "${UPDATED_BRANCH}" == "main" ]] || [[ "${UPDATED_BRANCH}" == "master" ]]
then
  OS_REGION_NAME="Fra1"
  OS_AUTH_URL="https://fra1.citycloud.com:5000"
fi
echo "Running in region: $OS_REGION_NAME"

# Delete executer vm
echo "Deleting executer VM ${TEST_EXECUTER_VM_NAME}."
openstack server delete "${TEST_EXECUTER_VM_NAME}"
echo "Executer VM ${TEST_EXECUTER_VM_NAME} is deleted."

# Delete executer VM port
echo "Deleting executer VM port ${TEST_EXECUTER_PORT_NAME}."
openstack port delete "${TEST_EXECUTER_PORT_NAME}"
echo "Executer VM port ${TEST_EXECUTER_PORT_NAME} is deleted."
