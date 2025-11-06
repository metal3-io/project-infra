#!/usr/bin/env bash

set -x

export QUICK_START_BASE=${QUICK_START_BASE:="$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")"}

# Delete the management cluster
kind delete cluster 2>/dev/null || true

# Stop and remove containers
docker stop dnsmasq 2>/dev/null || true
docker rm dnsmasq 2>/dev/null || true
docker stop image-server 2>/dev/null || true
docker rm image-server 2>/dev/null || true
docker stop sushy-tools 2>/dev/null || true
docker rm sushy-tools 2>/dev/null || true

# Cleanup VM from both system and session connections
virsh -c qemu:///system destroy bmh-vm-01 2>/dev/null || true
virsh -c qemu:///system undefine bmh-vm-01 --remove-all-storage --nvram 2>/dev/null || true
virsh -c qemu:///session destroy bmh-vm-01 2>/dev/null || true
virsh -c qemu:///session undefine bmh-vm-01 --remove-all-storage --nvram 2>/dev/null || true

# Cleanup network
virsh -c qemu:///system net-destroy baremetal-e2e 2>/dev/null || true
virsh -c qemu:///system net-undefine baremetal-e2e 2>/dev/null || true

# Remove generated files
rm -rf "${QUICK_START_BASE}/bmh-vm-01.xml" 2>/dev/null || true
rm -rf "${QUICK_START_BASE}/test-cluster-kubeconfig.yaml" 2>/dev/null || true

# Cleanup network interfaces and docker network
sudo ip link del metalend 2>/dev/null || true
docker network rm kind 2>/dev/null || true

# Cleanup iptables rules
sudo iptables -D FORWARD -i kind -o metal3 -j ACCEPT 2>/dev/null || true
sudo iptables -D FORWARD -i metal3 -o kind -j ACCEPT 2>/dev/null || true

echo "Cleanup complete"