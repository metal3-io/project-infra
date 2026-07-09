#!/usr/bin/env bash
set +x

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
. "${SCRIPTDIR}"/lib/vars.sh

KIND_PROVISIONING_NETWORK="${KIND_PROVISIONING_NETWORK:-bml-provisioning}"
KIND_EXTERNAL_NETWORK="${KIND_EXTERNAL_NETWORK:-bml-external}"

set -x

sudo ip link delete external || true
sudo ip link delete ironic-peer || true
sudo ip link delete ironicendpoint || true
sudo ip link delete provisioning || true

kind delete cluster --name "${KIND_CLUSTER_NAME:-bml}" || true
minikube delete || true

sudo docker network rm "${KIND_PROVISIONING_NETWORK}" || true
sudo docker network rm "${KIND_EXTERNAL_NETWORK}" || true

# Clean up Docker containers safely
docker ps -a -q | xargs -r docker stop
docker ps -a -q | xargs -r docker rm

sudo rm -rf /opt/metal3-dev-env/ironic/*
sudo rm -rf  /home/metal3ci/go/src/github.com/metal3-io/*

sudo rm -rf "${HOME}"/.minikube
sudo rm -rf "${CAPI_CONFIG_DIR}"
