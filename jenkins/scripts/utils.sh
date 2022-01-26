#! /usr/bin/env bash

# Global defines for Airship CI infrastructure
# ============================================

CI_EXT_NET="airship-ci-ext-net"
CI_EXT_SUBNET_CIDR="10.100.10.0/24"
CI_FLOATING_IP_NET="ext-net"
CI_METAL3_IMAGE="airship-ci-ubuntu-metal3-img"
CI_METAL3_CENTOS_IMAGE="airship-ci-centos-metal3-img"


# Description:
# Generates subnet name from Network name.
#
# Example:
#   Input: "airship-network"
#   Output: "airship-network-subnet"
#
get_subnet_name() {
  echo "${1:?}-subnet"
}

# Description:
# Waits for SSH connection to come up for a server
#
# Usage:
#   wait_for_ssh <ssh_user> <ssh_key_path> <server>
#
wait_for_ssh() {
  local USER KEY SERVER

  USER="${1:?}"
  KEY="${2:?}"
  SERVER="${3:?}"

  echo "Waiting for SSH connection to Host[${SERVER}]"
  until ssh -o ConnectTimeout=2 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -i "${KEY}" \
    "${USER}"@"${SERVER}" echo "SSH to host is up" > /dev/null 2>&1
        do sleep 1
  done

  echo "SSH connection to host[${SERVER}] is up."
}
