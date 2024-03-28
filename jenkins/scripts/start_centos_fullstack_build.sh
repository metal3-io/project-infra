#!/bin/bash
# Fail the script if any command fails
set -eu

# VM configuration variables
BUILDER_VM_NAME="${VM_NAME}"
BUILDER_PORT_NAME="${BUILDER_PORT_NAME:-${BUILDER_VM_NAME}-int-port}"
BUILDER_FLAVOR="${BUILDER_FLAVOR:-8C-16GB-200GB}"
CI_DIR="$(dirname "$(readlink -f "${0}")")"
IPA_BUILDER_SCRIPT_NAME="${IPA_BUILDER_SCRIPT_NAME:-build_ipa.sh}"
CI_EXT_NET="metal3-ci-ext-net"
IMAGE_NAME="metal3-ci-ubuntu-metal3-img"

# shellcheck source=jenkins/scripts/openstack/utils.sh
source "${CI_DIR}/openstack/utils.sh"

# Creating new port, needed to immediately get the ip
EXT_PORT_ID="$(openstack port create -f json \
  --network "${CI_EXT_NET}" \
  --fixed-ip subnet="$(get_subnet_name "${CI_EXT_NET}")" \
  "${BUILDER_PORT_NAME}" | jq -r '.id')"

# Create new builder vm
openstack server create -f json \
  --image "${IMAGE_NAME}" \
  --flavor "${BUILDER_FLAVOR}" \
  --port "${EXT_PORT_ID}" \
  "${BUILDER_VM_NAME}" | jq -r '.id'

# Get the IP
BUILDER_IP="$(openstack port show -f json "${BUILDER_PORT_NAME}" \
  | jq -r '.fixed_ips[0].ip_address')"

echo "Waiting for the host ${BUILDER_VM_NAME} to come up"
# Wait for the host to come up
wait_for_ssh "${METAL3_CI_USER}" "${METAL3_CI_USER_KEY}" "${BUILDER_IP}"

# Send IPA & Ironic script to remote executer
scp \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -i "${METAL3_CI_USER_KEY}" \
  "${CI_DIR}/${IPA_BUILDER_SCRIPT_NAME}" \
  "${CI_DIR}/../artifactory/utils.sh" \
  "${CI_DIR}/../harbor/harbor_utils.sh" \
  "${CI_DIR}/run_build_ironic.sh" \
  "${CI_DIR}/bmh-patch-short-serial.yaml" \
  "${METAL3_CI_USER}@${BUILDER_IP}:/tmp/" > /dev/null

# Send IPA builder custom element to remote executer
scp \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -i "${METAL3_CI_USER_KEY}" \
  -r "${CI_DIR}/ipa_builder_elements" \
  "${METAL3_CI_USER}@${BUILDER_IP}:/tmp/" > /dev/null

echo "Running Ironic image building script"
# Execute remote script
# shellcheck disable=SC2029
ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=10 \
  -i "${METAL3_CI_USER_KEY}" \
  "${METAL3_CI_USER}"@"${BUILDER_IP}" \
  PATH=/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:/bin \
  IRONIC_REFSPEC="${IRONIC_REFSPEC:-}" \
  IRONIC_IMAGE_REPO_COMMIT="${IRONIC_IMAGE_REPO_COMMIT:-}" \
  IRONIC_IMAGE_BRANCH="${IRONIC_IMAGE_BRANCH:-}" \
  IRONIC_INSPECTOR_REFSPEC="${IRONIC_INSPECTOR_REFSPEC:-}" \
  DOCKER_USER="${DOCKER_USER}" \
  DOCKER_PASSWORD="${DOCKER_PASSWORD}" /tmp/run_build_ironic.sh

IPA_REPO="${IPA_REPO:-https://opendev.org/openstack/ironic-python-agent.git}"
IPA_BRANCH="${IPA_BRANCH:-master}"
IPA_REF="${IPA_REF:-HEAD}"
IPA_BUILDER_REPO="${IPA_BUILDER_REPO:-https://opendev.org/openstack/ironic-python-agent-builder.git}"
IPA_BUILDER_BRANCH="${IPA_BUILDER_BRANCH:-master}"
IPA_BUILDER_COMMIT="${IPA_BUILDER_COMMIT:-HEAD}"
METAL3_DEV_ENV_REPO="${METAL3_DEV_ENV_REPO:-https://github.com/metal3-io/metal3-dev-env.git}"
METAL3_DEV_ENV_BRANCH="${METAL3_DEV_ENV_BRANCH:-main}"
METAL3_DEV_ENV_COMMIT="${METAL3_DEV_ENV_COMMIT:-HEAD}"
BMOREPO="${BMOREPO:-https://github.com/metal3-io/baremetal-operator.git}"
BMO_BRANCH="${BMO_BRANCH:-main}"
BMO_COMMIT="${BMO_COMMIT:-HEAD}"
CAPM3_REPO="${CAPM3_REPO:-https://github.com/metal3-io/cluster-api-provider-metal3.git}"
CAPM3_BRANCH="${CAPM3_BRANCH:-main}"
CAPM3_COMMIT="${CAPM3_COMMIT:-HEAD}"
IPAM_REPO="${IPAM_REPO:-https://github.com/metal3-io/ip-address-manager.git}"
IPAM_BRANCH="${IPAM_BRANCH:-main}"
IPAM_COMMIT="${IPAM_COMMIT:-HEAD}"
CAPI_REPO="${CAPI_REPO:-https://github.com/kubernetes-sigs/cluster-api.git}"
CAPI_BRANCH="${CAPI_BRANCH:-main}"
CAPI_COMMIT="${CAPI_COMMIT:-HEAD}"
BUILD_CAPM3_LOCALLY="${BUILD_CAPM3_LOCALLY:-true}"
BUILD_BMO_LOCALLY="${BUILD_BMO_LOCALLY:-true}"
BUILD_IPAM_LOCALLY="${BUILD_IPAM_LOCALLY:-true}"
BUILD_CAPI_LOCALLY="${BUILD_CAPI_LOCALLY:-false}"

echo "Running IPA, CAPI, CAPM3, IPAM, BMO, DEV-ENV building, deploying, testing scripts"
# Execute remote script
# shellcheck disable=SC2029
ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=10 \
  -i "${METAL3_CI_USER_KEY}" \
  "${METAL3_CI_USER}"@"${BUILDER_IP}" \
  PATH=/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:/bin \
  RT_USER="${RT_USER}" RT_TOKEN="${RT_TOKEN}" GITHUB_TOKEN="${GITHUB_TOKEN}" STAGING="${STAGING}" \
  IPA_REPO="${IPA_REPO}" IPA_BRANCH="${IPA_BRANCH}" IPA_REF="${IPA_REF}" \
  IPA_BUILDER_REPO="${IPA_BUILDER_REPO}" IPA_BUILDER_BRANCH="${IPA_BUILDER_BRANCH}" IPA_BUILDER_COMMIT="${IPA_BUILDER_COMMIT}" \
  METAL3_DEV_ENV_REPO="${METAL3_DEV_ENV_REPO}" METAL3_DEV_ENV_BRANCH="${METAL3_DEV_ENV_BRANCH}" METAL3_DEV_ENV_COMMIT="${METAL3_DEV_ENV_COMMIT}" \
  BMOREPO="${BMOREPO}" BMO_BRANCH="${BMO_BRANCH}" BMO_COMMIT="${BMO_COMMIT}" \
  CAPM3_REPO="${CAPM3_REPO}" CAPM3_BRANCH="${CAPM3_BRANCH}" CAPM3_COMMIT="${CAPM3_COMMIT}" \
  IPAM_REPO="${IPAM_REPO}" IPAM_BRANCH="${IPAM_BRANCH}" IPAM_COMMIT="${IPAM_COMMIT}" \
  CAPI_REPO="${CAPI_REPO}" CAPI_BRANCH="${CAPI_BRANCH}" CAPI_COMMIT="${CAPI_COMMIT}" \
  BUILD_CAPM3_LOCALLY="${BUILD_CAPM3_LOCALLY}" BUILD_BMO_LOCALLY="${BUILD_BMO_LOCALLY}" \
  BUILD_IPAM_LOCALLY="${BUILD_IPAM_LOCALLY}" BUILD_CAPI_LOCALLY="${BUILD_CAPI_LOCALLY}" \
  "/tmp/${IPA_BUILDER_SCRIPT_NAME}"