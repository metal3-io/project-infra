#!/usr/bin/env bash

set -eu

# Description:
#   Cleans the executer vm after integration tests
#   Requires:
#     - source stackrc file
# Usage:
#  integration_delete.sh
#
BARE_METAL_LAB="${BARE_METAL_LAB:-false}"
KEEP_TEST_ENV="${KEEP_TEST_ENV:-false}"
# set GINKGO_FOCUS to empty value if it is not set
GINKGO_FOCUS="${GINKGO_FOCUS:-}"

CI_DIR="$(dirname "$(readlink -f "${0}")")"
IMAGE_OS="${IMAGE_OS:-ubuntu}"
BUILD_TAG="${BUILD_TAG:-logs_integration_tests}"

# shellcheck disable=SC1091
source "${CI_DIR}/utils.sh"

TEST_EXECUTER_PORT_NAME="${TEST_EXECUTER_PORT_NAME:-${TEST_EXECUTER_VM_NAME}-int-port}"

# Run:
#   - e2e features, clusterctl-upgrade tests in the Frankfurt region
#   - ansible, e2e, basic integration, k8s-upgrade tests in Karlskrona region
#   - keep tests in dev2 project Karlskrona region
if [[ "${KEEP_TEST_ENV}" == "true" ]]; then
    export OS_PROJECT_NAME="dev2"
    export OS_TENANT_NAME="dev2"
elif [[ "${GINKGO_FOCUS}" == "pivoting" ]] || [[ "${GINKGO_FOCUS}" == "remediation" ]] ||
        [[ "${GINKGO_FOCUS}" == "features" ]] || [[ "${GINKGO_FOCUS}" == "clusterctl-upgrade" ]]; then
    export OS_REGION_NAME="Fra1"
    export OS_AUTH_URL="https://fra1.citycloud.com:5000"
fi

if [[ "${BARE_METAL_LAB}" != "true" ]]; then
    echo "Running in region: ${OS_REGION_NAME}"
fi

# Get the IP
if [[ "${BARE_METAL_LAB}" == true ]]; then
    TEST_EXECUTER_IP="192.168.1.3"
else
    TEST_EXECUTER_IP="$(openstack port show -f json "${TEST_EXECUTER_PORT_NAME}" |
        jq -r '.fixed_ips[0].ip_address')"
    if [[ "${OS_REGION_NAME}" == "Fra1" ]] || [[ "${OS_PROJECT_NAME}" == "dev2" ]]; then
        FLOATING_IP="$(openstack floating ip list --fixed-ip-address "${TEST_EXECUTER_IP}" \
            -c "Floating IP Address" -f value)"
        TEST_EXECUTER_IP="${FLOATING_IP}"
    fi
fi

declare -a SSH_OPTIONS=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=10
    -i "${METAL3_CI_USER_KEY}"
    )

# Send Remote script to Executer
scp \
    "${SSH_OPTIONS[@]}" \
    "${CI_DIR}/files/run_fetch_logs.sh" \
    "${METAL3_CI_USER}@${TEST_EXECUTER_IP}:/tmp/" > /dev/null

echo "Fetching logs"
# Execute remote script
# shellcheck disable=SC2029
ssh \
    "${SSH_OPTIONS[@]}" \
    "${METAL3_CI_USER}"@"${TEST_EXECUTER_IP}" \
    PATH=/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:/bin \
    /tmp/run_fetch_logs.sh "logs-${BUILD_TAG}.tgz" \
    "logs-${BUILD_TAG}" "${IMAGE_OS}" "${TESTS_FOR}"

# fetch logs tarball
scp \
    "${SSH_OPTIONS[@]}" \
    "${METAL3_CI_USER}@${TEST_EXECUTER_IP}:logs-${BUILD_TAG}.tgz" \
    "./" > /dev/null
