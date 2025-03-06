#!/usr/bin/env bash

set -eux

REPO_NAME="${1:-metal3-dev-env}"
IMAGE_OS="${2:-ubuntu}"

# shellcheck disable=SC1091
source "/tmp/vars.sh"

if [[ "${IMAGE_OS}" == "ubuntu" ]]; then
    export CONTAINER_RUNTIME="docker"
    export EPHEMERAL_CLUSTER="kind"
else
    export EPHEMERAL_CLUSTER="minikube"
fi
if [[ "${REPO_NAME}" == "metal3-dev-env" ]]; then
    pushd "${HOME}/tested_repo"
else
    pushd "${HOME}/metal3"
fi
make clean
