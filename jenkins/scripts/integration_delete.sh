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

# Delete executer vm
echo "Deleting executer VM."
openstack server delete "${TEST_EXECUTER_VM_NAME}"


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
    echo "Deleting executer volume."
    openstack volume delete "${TEST_EXECUTER_VM_NAME}"
fi

# Delete executer VM port
echo "Deleting executer VM port."
openstack port delete "${TEST_EXECUTER_PORT_NAME}"