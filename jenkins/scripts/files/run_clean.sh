#!/bin/bash

set -eux

REPO_NAME="${1:-metal3-dev-env}"
IMAGE_OS="${2:-ubuntu}"
TESTS_FOR="${3:-e2e_tests}"

if [ "${IMAGE_OS}" == "ubuntu" ]; then
  export CONTAINER_RUNTIME="docker"
  export EPHEMERAL_CLUSTER="kind"
else
  export EPHEMERAL_CLUSTER="minikube"
fi
if [[ ("${TESTS_FOR}" != "e2e_tests" && "${REPO_NAME}" == "metal3-dev-env") ||
      ("${TESTS_FOR}" == "e2e_tests" && "${REPO_NAME}" == "cluster-api-provider-metal3") 
  ]]; then
  pushd tested_repo
else
  pushd metal3
fi
make clean
