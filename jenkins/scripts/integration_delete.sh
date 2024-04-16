#!/usr/bin/env bash

set -eu

# Description:
# Runs in every single main job and in jobs triggered within the PR in metal3 repos.
# Consumed by integration_tests.pipeline and cleans the executer vm/volume and port after
# integration tests.
#   Requires:
#     - source openstack.rc file
# Usage:
#  integration_delete.sh
#

# set GINKGO_FOCUS to empty value if it is not set
GINKGO_FOCUS="${GINKGO_FOCUS:-}"

CI_DIR="$(dirname "$(readlink -f "${0}")")"

# shellcheck disable=SC1091
source "${CI_DIR}/utils.sh"

TEST_EXECUTER_PORT_NAME="${TEST_EXECUTER_PORT_NAME:-${TEST_EXECUTER_VM_NAME}-int-port}"
TEST_EXECUTER_FIP_TAG="${TEST_EXECUTER_FIP_TAG:-${TEST_EXECUTER_VM_NAME}-floating-ip}"

# Run:
#   - e2e features, clusterctl-upgrade tests in the Frankfurt region
#   - ansible, e2e, basic integration, k8s-upgrade tests in Karlskrona region
#   - keep tests in dev2 project Karlskrona region
if [[ "${GINKGO_FOCUS}" == "pivoting" ]] || [[ "${GINKGO_FOCUS}" == "remediation" ]] ||
        [[ "${GINKGO_FOCUS}" == "features" ]] || [[ "${GINKGO_FOCUS}" == "clusterctl-upgrade" ]]; then
    export OS_REGION_NAME="Fra1"
    export OS_AUTH_URL="https://fra1.citycloud.com:5000"
fi
echo "Running in region: ${OS_REGION_NAME}"

if [[ "${OS_REGION_NAME}" == "Fra1" ]] || [[ "${OS_PROJECT_NAME}" == "dev2" ]]; then
    # Find executer floating ip
    TEST_EXECUTER_FIP_ID="$(openstack floating ip list --tags "${TEST_EXECUTER_FIP_TAG}" -f value -c ID)"

    # Delete executer floating ip
    echo "Deleting executer floating IP ${TEST_EXECUTER_FIP_ID}."
    echo "${TEST_EXECUTER_FIP_ID}" | xargs openstack floating ip delete
    echo "Executer floating IP ${TEST_EXECUTER_FIP_ID} is deleted."

    # Check and delete orphaned floating IPs
    echo "Checking if there are any existing orphaned floating IPs"
    ORPHANED_FLOATING_IP_LIST="$(openstack floating ip list --status "DOWN" --column "ID" -f json | jq --raw-output '.[]."ID"')"
    if [[ -z "${ORPHANED_FLOATING_IP_LIST}" ]]; then
        echo "Orphaned floating IPs are not found."
    else
        echo "Deleting all orphaned floating IP addresses."
        for floating_ip in ${ORPHANED_FLOATING_IP_LIST}; do
            openstack floating ip delete "${floating_ip}"
        done
    fi
fi

# Delete executer vm
echo "Deleting executer VM ${TEST_EXECUTER_VM_NAME}."
openstack server delete "${TEST_EXECUTER_VM_NAME}"
echo "Executer VM ${TEST_EXECUTER_VM_NAME} is deleted."

# Delete executer VM port
echo "Deleting executer VM port ${TEST_EXECUTER_PORT_NAME}."
openstack port delete "${TEST_EXECUTER_PORT_NAME}"
echo "Executer VM port ${TEST_EXECUTER_PORT_NAME} is deleted."
