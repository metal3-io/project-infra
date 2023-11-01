#!/usr/bin/env bash

# Global defines for Airship CI infrastructure
# ============================================

export CI_EXT_NET="metal3-ci-ext-net"
export CI_EXT_SUBNET_CIDR="10.100.10.0/24"
export CI_FLOATING_IP_NET="ext-net"
export CI_METAL3_IMAGE="metal3-ci-ubuntu-metal3-img"
export CI_METAL3_CENTOS_IMAGE="metal3-ci-centos-metal3-img"

# Description:
# Generates subnet name from Network name.
#
# Example:
#   Input: "metal3-network"
#   Output: "metal3-network-subnet"
#
get_subnet_name()
{
    echo "${1:?}-subnet"
}

# Description:
# Waits for SSH connection to come up for a server
#
# Usage:
#   wait_for_ssh <ssh_user> <ssh_key_path> <server> <ssh_jump_host>
#
wait_for_ssh()
{
    local USER KEY SERVER

    USER="${1:?}"
    KEY="${2:?}"
    SERVER="${3:?}"
    JUMP_HOST="${4:-}"

    echo "Waiting for SSH connection to Host[${SERVER}]"
    if [[ -n "${JUMP_HOST}" ]]; then
        until ssh -o ConnectTimeout=2 \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -i "${KEY}" \
            -J "${USER}"@"${JUMP_HOST}" \
            "${USER}"@"${SERVER}" echo "SSH to host is up" > /dev/null 2>&1; do
            sleep 1
        done
    else
        until ssh -o ConnectTimeout=2 \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -i "${KEY}" \
            "${USER}"@"${SERVER}" echo "SSH to host is up" > /dev/null 2>&1; do
            sleep 1
        done
    fi
    echo "SSH connection to host[${SERVER}] is up."
}

# Description:
# Check that cloud-init completed successfully.
#
# Usage:
#   vm_healthy <ssh_user> <ssh_key_path> <server> <ssh_jump_host>
vm_healthy()
{
    local USER KEY SERVER

    USER="${1:?}"
    KEY="${2:?}"
    SERVER="${3:?}"
    SSH_JUMP_HOST="${4:-}"

    if [[ -n "${SSH_JUMP_HOST}" ]]; then
        cloud_init_status=$(ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null -i "${KEY}" -J "${SSH_JUMP_HOST}@${SERVER}" \
            "${USER}"@"${SERVER}" cloud-init status --long --wait)
    else
        cloud_init_status=$(ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null -i "${KEY}" \
            "${USER}"@"${SERVER}" cloud-init status --long --wait)
    fi
    if echo "${cloud_init_status}" | grep "error"; then
        echo "There was a cloud-init error:"
        echo "${cloud_init_status}"
        return 1
    else
        echo "Cloud-init completed successfully!"
        return 0
    fi
}
