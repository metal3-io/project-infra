#!/usr/bin/env bash

set -eu

# Description:
#   Cleans the baremetal lab after successful integration tests
#
# Usage:
#  cleanup_bml.sh
#
echo "Cleaning up the lab"
# Execute remote script
# shellcheck disable=SC2029

TEST_EXECUTER_IP="192.168.1.3"

ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=10 \
    -o SendEnv="BML_ILO_USERNAME" \
    -o SendEnv="BML_ILO_PASSWORD" \
    -o SendEnv="GITHUB_TOKEN" \
    -o SendEnv="REPO_NAME" \
    -o SendEnv="BML_METAL3_DEV_ENV_REPO" \
    -o SendEnv="BML_METAL3_DEV_ENV_BRANCH" \
    -o SendEnv="PR_ID" \
    -i "${METAL3_CI_USER_KEY}" \
    "${METAL3_CI_USER}"@"${TEST_EXECUTER_IP}" \
    ANSIBLE_FORCE_COLOR=true ansible-playbook -v /tmp/bare_metal_lab/cleanup-lab.yaml --skip-tags "clone"
