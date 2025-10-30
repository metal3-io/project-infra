#!/usr/bin/env bash

set -eu

# Description:
#   Cleans the baremetal lab after successful integration tests
#
# Usage:
#  cleanup_bml.sh
#
export EXTERNAL_VLAN_ID="${EXTERNAL_VLAN_ID:-3}"
export BOOTSTRAP_CLUSTER="${BOOTSTRAP_CLUSTER:-"minikube"}"
export CAPI_VERSION="${CAPI_VERSION:-v1beta2}"
export CAPM3_VERSION="${CAPM3_VERSION:-v1beta1}"
export CAPM3RELEASEBRANCH="${CAPM3RELEASEBRANCH:-main}"
export BMORELEASEBRANCH="${BMORELEASEBRANCH:-main}"
export IMAGE_OS="${IMAGE_OS:-centos}"
export NUM_NODES="${NUM_NODES:-2}"
export CONTROL_PLANE_MACHINE_COUNT="${CONTROL_PLANE_MACHINE_COUNT:-1}"
export WORKER_MACHINE_COUNT="${WORKER_MACHINE_COUNT:-1}"

CI_DIR="$(dirname "$(readlink -f "${0}")")"

echo "Cleaning up the lab"

ANSIBLE_FORCE_COLOR=true ansible-playbook -v "${CI_DIR}"/cleanup-lab.yaml --skip-tags "clone"
