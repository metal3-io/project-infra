#!/usr/bin/env bash
set +x

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
. "${SCRIPTDIR}"/lib/vars.sh

set -x

sudo ip link delete external
sudo ip link delete ironic-peer
sudo ip link delete ironicendpoint
sudo ip link delete provisioning

# Destroy and undefine the libvirt networks
sudo virsh net-destroy provisioning
sudo virsh net-destroy external

sudo virsh net-undefine provisioning
sudo virsh net-undefine external

minikube delete

# Clean up Docker containers safely
docker ps -a -q | xargs -r docker stop
docker ps -a -q | xargs -r docker rm

# sudo rm -rf /opt/metal3-dev-env/ironic/*
sudo rm -rf  /home/metal3ci/go/src/github.com/metal3-io/*

#sudo rm -rf "${HOME}"/.minikube
sudo rm -rf "${CAPI_CONFIG_DIR}"
