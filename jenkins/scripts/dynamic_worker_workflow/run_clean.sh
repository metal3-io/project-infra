#!/usr/bin/env bash

set -eux

if [[ "${IMAGE_OS}" == "ubuntu" ]]; then
    export CONTAINER_RUNTIME="docker"
    export EPHEMERAL_CLUSTER="kind"
else
    export EPHEMERAL_CLUSTER="minikube"
fi

if [[ "${REPO_NAME}" == "metal3-dev-env" ]] ||
   [[ "${REPO_NAME}" == "cluster-api-provider-metal3" ]] \
    ; then
    pushd tested_repo
else
    pushd metal3
fi

make clean
