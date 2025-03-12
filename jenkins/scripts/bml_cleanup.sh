#!/usr/bin/env bash

set -eu

# Description:
#   Cleans the baremetal lab after successful integration tests
#
# Usage:
#  cleanup_bml.sh
#

CI_DIR="$(dirname "$(readlink -f "${0}")")"

echo "Cleaning up the lab"

ANSIBLE_FORCE_COLOR=true ansible-playbook -v "${CI_DIR}"/bare_metal_lab/cleanup-lab.yaml --skip-tags "clone"
