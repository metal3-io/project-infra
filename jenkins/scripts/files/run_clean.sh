#!/bin/bash

set -eux

REPO_NAME="${1:-metal3-dev-env}"
DISTRIBUTION="${2:-ubuntu}"

if [ "${DISTRIBUTION}" == "ubuntu" ]; then
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
