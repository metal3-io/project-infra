#!/usr/bin/env bash

# shellcheck disable=SC1091
source lib/vars.sh

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

docker stop $(docker ps -a -q)
docker rm $(docker ps -a -q)

# sudo rm -rf /opt/metal3-dev-env/ironic/*
sudo rm -rf  /home/metal3ci/go/src/github.com/metal3-io/*

#sudo rm -rf "${HOME}"/.minikube
sudo rm -rf "${CAPI_CONFIG_DIR}"
