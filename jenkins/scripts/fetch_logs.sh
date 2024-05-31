#!/usr/bin/env bash

set -eu

# Description:
#   Fetches logs from Executer machine
# Usage:
#  fetch_logs.sh
#


CI_DIR="$(dirname "$(readlink -f "${0}")")"
IMAGE_OS="${IMAGE_OS:-ubuntu}"
BUILD_TAG="${BUILD_TAG:-logs_integration_tests}"

# shellcheck disable=SC1091
source "${CI_DIR}/utils.sh"

TEST_EXECUTER_IP="192.168.1.3"


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
    "logs-${BUILD_TAG}" "${IMAGE_OS}"

# fetch logs tarball
scp \
    "${SSH_OPTIONS[@]}" \
    "${METAL3_CI_USER}@${TEST_EXECUTER_IP}:logs-${BUILD_TAG}.tgz" \
    "./" > /dev/null
