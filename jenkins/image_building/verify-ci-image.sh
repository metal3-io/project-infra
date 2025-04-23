#!/usr/bin/env bash

set -eux

# TODO: make a common script for this instead of having 2 almost identical scripts
verify_ci_image() {
    current_dir="$(dirname "$(readlink -f "${0}")")"

    # So that no extra components are built later
    export IMAGE_TESTING="true"

    # Run "make clean" after test, so that next job can start from clean state
    export CLEANUP_AFTERWARDS="${CLEANUP_AFTERWARDS:-false}"

    # Similar config to periodic integration tests
    export REPO_BRANCH="main"
    export REPO_ORG="metal3-io"
    export REPO_NAME="metal3-dev-env"
    export UPDATED_REPO="metal3-io/metal3-dev-env"
    export UPDATED_BRANCH="main"
    export NUM_NODES=2

    export IRONIC_INSTALL_TYPE="rpm"

    "${current_dir}/../scripts/dynamic_worker_workflow/dev_env_integration_tests.sh"
}

# If the script was run directly (i.e. not sourced), run the verify_ci_image func
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    verify_ci_image "$@"
fi
