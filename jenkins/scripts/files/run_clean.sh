#!/bin/bash

set -eux

REPO_NAME="${1:-metal3-dev-env}"
IMAGE_OS="${2:-ubuntu}"

if [ "${IMAGE_OS}" == "ubuntu" ]; then
  export CONTAINER_RUNTIME="docker"
  export EPHEMERAL_CLUSTER="kind"
else
  export EPHEMERAL_CLUSTER="minikube"
fi

if [ "${REPO_NAME}" == "metal3-dev-env" ]
then
  pushd tested_repo
else
  pushd metal3
fi
make clean
