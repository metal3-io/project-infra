#!/bin/bash
# Fail the script if any command fails
set -eu

# VM configuration variables
TEST_EXECUTER_VM_NAME="${TEST_EXECUTER_VM_NAME}"
TEST_EXECUTER_PORT_NAME="${TEST_EXECUTER_PORT_NAME:-${TEST_EXECUTER_VM_NAME}-int-port}"
TEST_EXECUTER_FIP_TAG="${TEST_EXECUTER_FIP_TAG:-${TEST_EXECUTER_VM_NAME}-floating-ip}"
TEST_EXECUTER_FLAVOR="${TEST_EXECUTER_FLAVOR:-2C-4GB-50GB}"
CI_DIR="$(dirname "$(readlink -f "${0}")")"
CI_EXT_NET="metal3-ci-ext-net"
IMAGE_NAME="metal3-ci-ubuntu-metal3-img"
IMAGE_OS="ubuntu"

# shellcheck disable=SC1090
source "${CI_DIR}/utils.sh"

# Creating new port, needed to immediately get the ip
EXT_PORT_ID="$(openstack port create -f json \
  --network "${CI_EXT_NET}" \
  --fixed-ip subnet="$(get_subnet_name "${CI_EXT_NET}")" \
  "${TEST_EXECUTER_PORT_NAME}" | jq -r '.id')"

# Create new builder vm
openstack server create -f json \
  --image "${IMAGE_NAME}" \
  --flavor "${TEST_EXECUTER_FLAVOR}" \
  --port "${EXT_PORT_ID}" \
  "${TEST_EXECUTER_VM_NAME}" | jq -r '.id'

# Get the IP
TEST_EXECUTER_IP="$(openstack port show -f json "${TEST_EXECUTER_PORT_NAME}" \
  | jq -r '.fixed_ips[0].ip_address')"

# Wait for the host to come up
for i in {1..6}; do
  echo "Waiting for the host ${TEST_EXECUTER_VM_NAME} to come up"
  # Wait for the host to come up
  wait_for_ssh "${OS_USERNAME}" "${METAL3_CI_USER_KEY}" "${TEST_EXECUTER_IP}"
  if vm_healthy "${OS_USERNAME}" "${METAL3_CI_USER_KEY}" "${TEST_EXECUTER_IP}"; then
    break
  else
    if [ ${i} -eq 5 ]; then
      echo "Server is still unhealthy after retry. Giving up."
      exit 1
    fi
    echo "Trying to create server again. Retry ${i}/5"
    echo "Deleting unhealthy server ${TEST_EXECUTER_VM_NAME}..."
    openstack server delete "${TEST_EXECUTER_VM_NAME}"
    echo "Server ${TEST_EXECUTER_VM_NAME} deleted."

    # Create new executer vm
    echo "Recreating server ${TEST_EXECUTER_VM_NAME}"
    openstack server create -f json \
      --image "${IMAGE_NAME}" \
      --flavor "${TEST_EXECUTER_FLAVOR}" \
      --port "${EXT_PORT_ID}" \
      "${TEST_EXECUTER_VM_NAME}" | jq -r '.id'
  fi
done

cat <<-EOF >> "${CI_DIR}/files/vars.sh"
DESTINATION_REPO="${DESTINATION_REPO}"
DESTINATION_BRANCH="${DESTINATION_BRANCH}"
SOURCE_REPO="${SOURCE_REPO}"
SOURCE_BRANCH="${SOURCE_BRANCH}"
PATCHFILE_CONTENT="${PATCHFILE_CONTENT}"
EOF


# Send Ironic script to remote executer
scp \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -i "${METAL3_CI_USER_KEY}" \
  "${CI_DIR}/ironic_build_test.sh" \
  "${CI_DIR}/files/vars.sh" \
  "${OS_USERNAME}@${TEST_EXECUTER_IP}:/tmp/" > /dev/null

echo "Running Ironic image building script (INSTALL_FROM_SOURCE)"
# Execute remote script
# shellcheck disable=SC2029
ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=10 \
  -i "${METAL3_CI_USER_KEY}" \
  "${OS_USERNAME}"@"${TEST_EXECUTER_IP}" \
  PATH="/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:/bin" \
  IRONIC_INSTALL_MODE="INSTALL_FROM_SOURCE" \
  "/tmp/ironic_build_test.sh"

echo "Running Ironic image building script (INSTALL_FROM_RPM)"
# Execute remote script
# shellcheck disable=SC2029
ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=10 \
  -i "${METAL3_CI_USER_KEY}" \
  "${OS_USERNAME}"@"${TEST_EXECUTER_IP}" \
  PATH="/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:/bin" \
  IRONIC_INSTALL_MODE="INSTALL_FROM_RPM" \
  "/tmp/ironic_build_test.sh"

echo "Running Ironic image building script (INSTALL_FROM_RPM_PATCH)"
# Execute remote script
# shellcheck disable=SC2029
ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=10 \
  -i "${METAL3_CI_USER_KEY}" \
  "${OS_USERNAME}"@"${TEST_EXECUTER_IP}" \
  PATH="/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:/bin" \
  IRONIC_INSTALL_MODE="INSTALL_FROM_RPM_PATCH" \
  "/tmp/ironic_build_test.sh"
