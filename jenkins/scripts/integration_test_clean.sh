#!/usr/bin/env bash

set -eu

# Description:
# Runs in every single main job and in jobs triggered within the PR in metal3 repos.
# Consumed by integration_tests.pipeline and cleans the integration test results by
# running 'make clean' target (check run_clean.sh script) eventually.
#   Requires:
#     - source openstack.rc file
# Usage:
#  integration_test_clean.sh
#

# set KEEP_TEST_ENV to false if it is not set
KEEP_TEST_ENV="${KEEP_TEST_ENV:-false}"
# set GINKGO_FOCUS to empty value if it is not set
GINKGO_FOCUS="${GINKGO_FOCUS:-}"

CI_DIR="$(dirname "$(readlink -f "${0}")")"

REPO_NAME="${REPO_NAME:-metal3-dev-env}"
IMAGE_OS="${IMAGE_OS:-ubuntu}"
SSH_JUMP_HOST="${SSH_JUMP_HOST:-}"

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
echo "Running in region: ${OS_REGION_NAME}"

# Get the IP
TEST_EXECUTER_IP="$(openstack port show -f json "${TEST_EXECUTER_PORT_NAME}" |
    jq -r '.fixed_ips[0].ip_address')"

if [[ "${OS_REGION_NAME}" == "Fra1" ]] || [[ "${OS_PROJECT_NAME}" == "dev2" ]]; then
    FLOATING_IP="$(openstack floating ip list --fixed-ip-address "${TEST_EXECUTER_IP}" \
        -c "Floating IP Address" -f value)"
    TEST_EXECUTER_IP="${FLOATING_IP}"
fi

if [[ -n "${SSH_JUMP_HOST}" ]]; then
# Send Remote script to Executer
scp \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -i "${METAL3_CI_USER_KEY}" \
    -J "${METAL3_CI_USER}"@"${SSH_JUMP_HOST}" \
    "${CI_DIR}/files/run_clean.sh" \
    "${METAL3_CI_USER}@${TEST_EXECUTER_IP}:/tmp/" > /dev/null

echo "Cleaning"
# Execute remote cleaning script
# shellcheck disable=SC2029
ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ServerAliveInterval=15 \
    -i "${METAL3_CI_USER_KEY}" \
    -J "${METAL3_CI_USER}"@"${SSH_JUMP_HOST}" \
    "${METAL3_CI_USER}"@"${TEST_EXECUTER_IP}" \
    PATH=/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:/bin \
    /tmp/run_clean.sh "${REPO_NAME}" "${IMAGE_OS}" "${TESTS_FOR}"
else
# Send Remote script to Executer
scp \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -i "${METAL3_CI_USER_KEY}" \
    "${CI_DIR}/files/run_clean.sh" \
    "${METAL3_CI_USER}@${TEST_EXECUTER_IP}:/tmp/" > /dev/null

echo "Cleaning"
# Execute remote cleaning script
# shellcheck disable=SC2029
ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ServerAliveInterval=15 \
    -i "${METAL3_CI_USER_KEY}" \
    "${METAL3_CI_USER}"@"${TEST_EXECUTER_IP}" \
    PATH=/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:/bin \
    /tmp/run_clean.sh "${REPO_NAME}" "${IMAGE_OS}" "${TESTS_FOR}"
fi
