#! /usr/bin/env bash

# Global defines for Airship CI infrastructure
# ============================================

CI_EXT_NET="airship-ci-ext-net"
CI_EXT_SUBNET_CIDR="10.100.10.0/24"
CI_METAL3_IMAGE="airship-ci-ubuntu-metal3-img"
CI_METAL3_CENTOS_IMAGE="airship-ci-centos-metal3-img"
#base centos stream image name built locally and pushed to CityCloud
#CI_METAL3_CENTOS_IMAGE="airship-ci-centos-stream-metal3-img_test"


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

# Description:
# Creates Openstack test executer volume.
#
# Usage:
#   create_test_executer_volume <base_volume_name_id> <test_executer_vm_name>
#
create_test_executer_volume() {
  local BASE_VOLUME_NAME_ID TEST_EXECUTER_VM_NAME

  BASE_VOLUME_NAME_ID="${1:?}"
  TEST_EXECUTER_VM_NAME="${2:?}"
    
  openstack volume create \
    --source "${BASE_VOLUME_NAME_ID}" \
    "${TEST_EXECUTER_VM_NAME}"
}

# Description:
# Waits for Openstack test executer volume to be available and if not
# retry volume creation again only once.
#
# Usage:
#   wait_for_volume <base_volume_name_id> <test_executer_vm_name>
#
wait_for_volume() {
  local BASE_VOLUME_NAME_ID TEST_EXECUTER_VM_NAME

  BASE_VOLUME_NAME_ID="${1:?}"
  TEST_EXECUTER_VM_NAME="${2:?}"

  retry=0
  until openstack volume show "${TEST_EXECUTER_VM_NAME}" -f json \
      | jq .status | grep "available"
  do
    sleep 10
    # Check if test executer volume creation is failed
    if [[ "$(openstack volume show "${TEST_EXECUTER_VM_NAME}" -f json \
      | jq .status)" == *"error"* ]];
    then
      # If test executer volume creation is failed, then retry volume creation only once
      if [ $retry -eq 0 ]; then
        openstack volume delete "${TEST_EXECUTER_VM_NAME}"
        sleep 10
        create_test_executer_volume "${BASE_VOLUME_NAME_ID}" "${TEST_EXECUTER_VM_NAME}"
        retry=1
      else
        exit 1
      fi
      continue
    fi
  done
}

# Description:
# Waits for Openstack resized test executer volume to be available and if not
# retry volume resizing again only once.
#
# Usage:
#   wait_for_resized_volume <base_volume_name_id> <test_executer_vm_name> <resized_vm_size>
#
wait_for_resized_volume() {
  local BASE_VOLUME_NAME_ID TEST_EXECUTER_VM_NAME RESIZED_VM_SIZE

  BASE_VOLUME_NAME_ID="${1:?}"
  TEST_EXECUTER_VM_NAME="${2:?}"
  RESIZED_VM_SIZE="${3:?}"

  resize_retry=0
  until openstack volume show "${TEST_EXECUTER_VM_NAME}" -f json \
    | jq .size | grep "${RESIZED_VM_SIZE}"
  do
    sleep 10
    if [[ "$(openstack volume show "${TEST_EXECUTER_VM_NAME}" -f json \
      | jq .status)" == *"error"* ]];
    then
      echo "Volume resizing is failed, retrying volume creation and resizing once again."
      # If volume resizing is failed, then retry volume creation and resizing only once
      if [ $resize_retry -eq 0 ]; then
        openstack volume delete "${TEST_EXECUTER_VM_NAME}"
        sleep 10
        create_test_executer_volume "${BASE_VOLUME_NAME_ID}" "${TEST_EXECUTER_VM_NAME}"
        wait_for_volume "${BASE_VOLUME_NAME_ID}" "${TEST_EXECUTER_VM_NAME}"
        openstack volume set --size "${RESIZED_VM_SIZE}" "${TEST_EXECUTER_VM_NAME}"
        resize_retry=1
      else
        exit 1
      fi
      continue
    fi
  done
}