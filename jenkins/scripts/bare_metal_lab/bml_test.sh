#!/usr/bin/env bash

set -xeu

# Description:
#   Runs the integration tests in the BML
# Usage:
#  bml_integration_test.sh
#
CI_DIR="$(dirname "$(readlink -f "${0}")")"

ACTION="${1}"

if [[ -z "${ACTION}" ]]; then
  echo "Action argument is required. Possible values: clean, deploy, teardown, run-test"
  exit 1
fi

case "${ACTION}" in
  clean)
    echo "Cleaning up the lab"
    ANSIBLE_FORCE_COLOR=true ansible-playbook -v "${CI_DIR}"/cleanup-lab.yaml
    ;;
  deploy)
    echo "Setting up the lab"
    ANSIBLE_FORCE_COLOR=true ansible-playbook -v "${CI_DIR}"/deploy-lab.yaml
    ;;
  run-test)
    echo "Running tests in the lab"
    ANSIBLE_FORCE_COLOR=true ansible-playbook -v "${CI_DIR}"/run-test.yaml
    ;;
  teardown)
    echo "Tearing down the lab"
    ANSIBLE_FORCE_COLOR=true ansible-playbook -v "${CI_DIR}"/teardown.yaml
    ;;
  pod-scale)
    echo "Scaling the lab"
    ANSIBLE_FORCE_COLOR=true ansible-playbook -b "${CI_DIR}"/pod_scaling/pod-scaling.yaml -i "${CI_DIR}"/pod_scaling/inventory.ini
    ;;
  *)
    echo "Unknown action: ${ACTION}. Possible values: clean, deploy, teardown, run-test"
    exit 1
    ;;
esac


# Run Pods Scaling test
#export ANSIBLE_CONFIG="${CI_DIR}"/tasks/pod_scaling/ansible.cfg
#ANSIBLE_FORCE_COLOR=true ansible-playbook -b "${CI_DIR}"/tasks/pod_scaling/pod-scaling.yaml -i "${CI_DIR}"/tasks/pod_scaling/inventory.ini
