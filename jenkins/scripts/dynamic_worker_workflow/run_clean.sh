#!/usr/bin/env bash

set -eux

if [[ "${IMAGE_OS}" == "ubuntu" ]]; then
    export CONTAINER_RUNTIME="docker"
    export BOOTSTRAP_CLUSTER="kind"
else
    export BOOTSTRAP_CLUSTER="minikube"
    export CONTAINER_RUNTIME="podman"
fi

if [[ "${REPO_NAME}" == "metal3-dev-env" ]] ||
   [[ "${REPO_NAME}" == "cluster-api-provider-metal3" ]] \
    ; then
    pushd "${HOME}/tested_repo"
else
    pushd "${HOME}/metal3"
fi

make clean

# Clean up test related files and directories
sudo rm -rf /home/metal3ci/tested_repo
sudo rm -rf /home/metal3ci/metal3
sudo rm -rf /opt/metal3-dev-env/*
sudo rm -rf /home/metal3ci/go/src/github.com/metal3-io/*
sudo rm -rf /home/metal3ci/.config/cluster-api/*

# Clean up Docker containers and images
sudo "${CONTAINER_RUNTIME}" container prune --force
sudo "${CONTAINER_RUNTIME}" image prune --force --all
sudo "${CONTAINER_RUNTIME}" volume prune --force
sudo "${CONTAINER_RUNTIME}" system prune --force --all
