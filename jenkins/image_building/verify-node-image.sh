#!/usr/bin/env bash

set -eux

verify_node_image() {
    current_dir="$(dirname "$(readlink -f "${0}")")"
    REPO_ROOT="$(realpath "${current_dir}/../..")"

    img_name="$1"
    IMAGE_DIR="${2:-"${REPO_ROOT}"}"

    # So that no extra components are built later
    export IMAGE_TESTING="true"

    # Run "make clean" after test, so that next job can start from clean state
    export CLEANUP_AFTERWARDS="${CLEANUP_AFTERWARDS:-false}"

    # Tests expect the image name to have the file type extension
    export IMAGE_NAME="${img_name}.qcow2"
    export IMAGE_OS="${IMAGE_OS}"
    export IMAGE_TYPE="${IMAGE_TYPE}"
    export IMAGE_LOCATION="${IMAGE_DIR}"

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

# If the script was run directly (i.e. not sourced), run the verify_node_image func
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    verify_node_image "$@"
fi
