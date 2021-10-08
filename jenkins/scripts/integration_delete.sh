#! /usr/bin/env bash

set -eu

# Description:
#   Cleans the executer vm after integration tests
#   Requires:
#     - source stackrc file
# Usage:
#  integration_delete.sh
#

CI_DIR="$(dirname "$(readlink -f "${0}")")"

# shellcheck disable=SC1090
source "${CI_DIR}/utils.sh"

TEST_EXECUTER_PORT_NAME="${TEST_EXECUTER_PORT_NAME:-${TEST_EXECUTER_VM_NAME}-int-port}"

if [[ "${TESTS_FOR}" == "feature_tests"* ]]
then
  OS_REGION_NAME="Fra1"
  OS_AUTH_URL="https://fra1.citycloud.com:5000"
fi

# Delete executer vm
echo "Deleting executer VM ${TEST_EXECUTER_VM_NAME}."
openstack server delete "${TEST_EXECUTER_VM_NAME}"
echo "Executer VM ${TEST_EXECUTER_VM_NAME} is deleted."

DISTRIBUTION="${DISTRIBUTION:-ubuntu}"
if [ "${DISTRIBUTION}" == "ubuntu" ]
then
    echo "Waiting until volume status is available, to proceed with proper volume deletion."
    until openstack volume show "${TEST_EXECUTER_VM_NAME}" -f json \
        | jq .status | grep "available"
    do
        sleep 10
        if [[ "$(openstack volume show "${TEST_EXECUTER_VM_NAME}" -f json \
            | jq .status)" == *"error"* ]];
        then
            exit 1
        fi
    done

    # Delete executer volume
    echo "Deleting executer volume ${TEST_EXECUTER_VM_NAME}."
    openstack volume delete "${TEST_EXECUTER_VM_NAME}"
    echo "Executer volume ${TEST_EXECUTER_VM_NAME} is deleted."
fi

# Delete executer VM port
echo "Deleting executer VM port ${TEST_EXECUTER_PORT_NAME}."
openstack port delete "${TEST_EXECUTER_PORT_NAME}"
echo "Executer VM port ${TEST_EXECUTER_PORT_NAME} is deleted."