#!/usr/bin/env bash

set -eu

# Description:
#   Runs the integration tests for metal3-dev-env in an executer vm
#   Requires:
#     - source stackrc file
#     - openstack ci infra should already be deployed.
#     - environment variables set:
#       - METAL3_CI_USER: Ci user for jumphost.
#       - METAL3_CI_USER_KEY: Path of the CI user private key for jumphost.
# Usage:
#  integration_test.sh
#

CI_DIR="$(dirname "$(readlink -f "${0}")")"

# shellcheck disable=SC1091
source "${CI_DIR}/utils.sh"

IMAGE_OS="${IMAGE_OS:-ubuntu}"
if [[ "${IMAGE_OS}" == "ubuntu" ]]; then
  IMAGE_NAME="${CI_METAL3_IMAGE}"
else
  IMAGE_NAME="${CI_METAL3_CENTOS_IMAGE}"
fi

REPO_ORG="${REPO_ORG:-metal3-io}"
REPO_NAME="${REPO_NAME:-metal3-dev-env}"
UPDATED_REPO="${UPDATED_REPO:-https://github.com/${REPO_ORG}/${REPO_NAME}.git}"
UPDATED_BRANCH="${UPDATED_BRANCH:-main}"
CAPI_VERSION="${CAPI_VERSION:-v1beta1}"
CAPM3_VERSION="${CAPM3_VERSION:-v1beta1}"
CAPM3RELEASEBRANCH="${CAPM3RELEASEBRANCH:-main}"
BMORELEASEBRANCH="${BMORELEASEBRANCH:-main}"
NUM_NODES="${NUM_NODES:-2}"
TESTS_FOR="${TESTS_FOR:-integration_test}"
BARE_METAL_LAB=false
TARGET_NODE_MEMORY="${TARGET_NODE_MEMORY:-4096}"
EPHEMERAL_TEST="${EPHEMERAL_TEST:-false}"
TEST_EXECUTER_PORT_NAME="${TEST_EXECUTER_PORT_NAME:-${TEST_EXECUTER_VM_NAME}-int-port}"
TEST_EXECUTER_FIP_TAG="${TEST_EXECUTER_FIP_TAG:-${TEST_EXECUTER_VM_NAME}-floating-ip}"
IRONIC_INSTALL_TYPE="${IRONIC_INSTALL_TYPE:-rpm}"
IRONIC_FROM_SOURCE="${IRONIC_FROM_SOURCE:-false}"
IRONIC_LOCAL_IMAGE=""
BUILD_IRONIC_LOCALLY=""
GINKGO_FOCUS="${GINKGO_FOCUS:-}"
GINKGO_SKIP="${GINKGO_SKIP:-}"
KEEP_TEST_ENV="${KEEP_TEST_ENV:-}"
UPGRADE_FROM_RELEASE="${UPGRADE_FROM_RELEASE:-}"
KUBERNETES_VERSION_UPGRADE_FROM="${KUBERNETES_VERSION_UPGRADE_FROM:-}"
KUBERNETES_VERSION_UPGRADE_TO="${KUBERNETES_VERSION_UPGRADE_TO:-}"
KUBECTL_SHA256="${KUBECTL_SHA256:-}"

if [[ "${IRONIC_INSTALL_TYPE}" == "source" ]]; then
  IRONIC_FROM_SOURCE="true"
  if [[ "${REPO_NAME}" == "ironic-image" ]]; then
    IRONIC_LOCAL_IMAGE="/home/${USER}/tested_repo"
  else
    BUILD_IRONIC_LOCALLY="true"
  fi
fi

# Run:
#   - e2e features, clusterctl-upgrade tests in the Frankfurt region
#   - ansible, e2e, basic integration, k8s-upgrade tests in Karlskrona region
#   - keep tests in dev2 project Karlskrona region
if [[ "${KEEP_TEST_ENV}" == "true" ]]; then
    export OS_PROJECT_NAME="dev2"
    export OS_TENANT_NAME="dev2"
elif [[ "${GINKGO_FOCUS}" == "pivoting" ]] || [[ "${GINKGO_FOCUS}" == "remediation" ]] ||
        [[ "${GINKGO_FOCUS}" == "features" ]] || [[ "${GINKGO_FOCUS}" == "clusterctl-upgrade" ]]; then
    export OS_REGION_NAME="Fra1"
    export OS_AUTH_URL="https://fra1.citycloud.com:5000"
fi
echo "Running in project: ${OS_PROJECT_NAME} region: ${OS_REGION_NAME}"

if [[ "${GINKGO_FOCUS}" == "pivoting" ]] || [[ "${GINKGO_FOCUS}" == "remediation" ]] ||
  [[ "${GINKGO_FOCUS}" == "features" ]] || [[ "${GINKGO_FOCUS}" == "k8s-upgrade" ]]; then
  # Four node cluster
  TEST_EXECUTER_FLAVOR="${TEST_EXECUTER_FLAVOR:-8C-24GB-300GB}"
elif [[ "${GINKGO_FOCUS}" == "clusterctl-upgrade" ]]; then
  # Five node cluster
  TEST_EXECUTER_FLAVOR="${TEST_EXECUTER_FLAVOR:-8C-32GB-300GB}"
else
  # Two node cluster
  TEST_EXECUTER_FLAVOR="${TEST_EXECUTER_FLAVOR:-4C-16GB-100GB}"
fi

# Creating new port, needed to immediately get the ip
EXT_PORT_ID="$(openstack port create -f json \
  --network "${CI_EXT_NET}" \
  --fixed-ip subnet="$(get_subnet_name "${CI_EXT_NET}")" \
  "${TEST_EXECUTER_PORT_NAME}" | jq -r '.id')"

# Create new executer vm
echo "Creating server ${TEST_EXECUTER_VM_NAME}"
openstack server create -f json \
  --image "${IMAGE_NAME}" \
  --flavor "${TEST_EXECUTER_FLAVOR}" \
  --port "${EXT_PORT_ID}" \
  "${TEST_EXECUTER_VM_NAME}" | jq -r '.id'

# Get the IP
TEST_EXECUTER_IP="$(openstack port show -f json "${TEST_EXECUTER_PORT_NAME}" |
  jq -r '.fixed_ips[0].ip_address')"

if [[ "${OS_REGION_NAME}" == "Fra1" ]] || [[ "${OS_PROJECT_NAME}" == "dev2" ]]; then
  # Create floating IP
  FLOATING_IP="$(openstack floating ip create -f value -c name \
    --tag "${TEST_EXECUTER_FIP_TAG}" \
    "${CI_FLOATING_IP_NET}")"

  if [[ -z "${FLOATING_IP}" ]]; then
    echo "No floating IP is available"
    exit 1
  fi
  TEST_EXECUTER_IP="${FLOATING_IP}"

  # Attach floating IP
  openstack server add floating ip \
    "${TEST_EXECUTER_VM_NAME}" \
    "${FLOATING_IP}"
fi

echo "Waiting for the host ${TEST_EXECUTER_VM_NAME} to come up"
# Wait for the host to come up
wait_for_ssh "${METAL3_CI_USER}" "${METAL3_CI_USER_KEY}" "${TEST_EXECUTER_IP}"
if ! vm_healthy "${METAL3_CI_USER}" "${METAL3_CI_USER_KEY}" "${TEST_EXECUTER_IP}"; then
  echo "Server is unhealthy. Giving up."
  exit 1
fi

TEMP_FILE_NAME=$(mktemp vars-XXXXXX.sh)
cat <<-EOF >>"${CI_DIR}/files/${TEMP_FILE_NAME}"
REPO_ORG="${REPO_ORG}"
REPO_NAME="${REPO_NAME}"
REPO_BRANCH="${REPO_BRANCH}"
UPDATED_REPO="${UPDATED_REPO}"
UPDATED_BRANCH="${UPDATED_BRANCH}"
CAPI_VERSION="${CAPI_VERSION}"
CAPM3_VERSION="${CAPM3_VERSION}"
CAPM3RELEASEBRANCH="${CAPM3RELEASEBRANCH}"
BMORELEASEBRANCH="${BMORELEASEBRANCH}"
IMAGE_OS="${IMAGE_OS}"
TARGET_NODE_MEMORY="${TARGET_NODE_MEMORY}"
NUM_NODES="${NUM_NODES}"
TESTS_FOR="${TESTS_FOR}"
BARE_METAL_LAB="${BARE_METAL_LAB}"
EPHEMERAL_TEST="${EPHEMERAL_TEST}"
IRONIC_FROM_SOURCE="${IRONIC_FROM_SOURCE}"
IRONIC_LOCAL_IMAGE="${IRONIC_LOCAL_IMAGE}"
BUILD_IRONIC_LOCALLY="${BUILD_IRONIC_LOCALLY}"
IRONIC_USE_MARIADB="${IRONIC_USE_MARIADB:-false}"
BUILD_MARIADB_IMAGE_LOCALLY="${BUILD_MARIADB_IMAGE_LOCALLY:-false}"
GINKGO_FOCUS="${GINKGO_FOCUS}"
GINKGO_SKIP="${GINKGO_SKIP}"
KEEP_TEST_ENV="${KEEP_TEST_ENV}"
UPGRADE_FROM_RELEASE="${UPGRADE_FROM_RELEASE}"
KUBERNETES_VERSION_UPGRADE_FROM="${KUBERNETES_VERSION_UPGRADE_FROM}"
KUBERNETES_VERSION_UPGRADE_TO="${KUBERNETES_VERSION_UPGRADE_TO}"
KUBECTL_SHA256="${KUBECTL_SHA256}"
EOF

# Write variables from pipeline for metal3 dev tools integration tests
if [[ -f "${CI_DIR}/files/devtoolsvars.sh" ]] && [[ "${REPO_NAME}" == "metal3-dev-tools" ]]; then
  cat "${CI_DIR}/files/devtoolsvars.sh" >>"${CI_DIR}/files/${TEMP_FILE_NAME}"
fi

# Only set these variables if they actually have values.
# If the variable is unset or empty (""), do nothing.
if [[ -n "${CAPIRELEASE:+x}" ]]; then
  echo "CAPIRELEASE=${CAPIRELEASE}" | tee --append "${CI_DIR}/files/${TEMP_FILE_NAME}"
fi
if [[ -n "${CAPM3RELEASE:+x}" ]]; then
  echo "CAPM3RELEASE=${CAPM3RELEASE}" | tee --append "${CI_DIR}/files/${TEMP_FILE_NAME}"
fi

cat "${CI_DIR}/integration_test_env.sh" >>"${CI_DIR}/files/${TEMP_FILE_NAME}"

# Send Remote script to Executer
scp \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -i "${METAL3_CI_USER_KEY}" \
  "${CI_DIR}/files/run_integration_tests.sh" \
  "${METAL3_CI_USER}@${TEST_EXECUTER_IP}:/tmp" >/dev/null

scp \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -i "${METAL3_CI_USER_KEY}" \
  "${CI_DIR}/files/${TEMP_FILE_NAME}" \
  "${METAL3_CI_USER}@${TEST_EXECUTER_IP}:/tmp/vars.sh" >/dev/null

# Clean temp vars.sh from the static worker
rm -f "${CI_DIR}/files/${TEMP_FILE_NAME}"

echo "Running the tests"
# Execute remote script
# shellcheck disable=SC2029
ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ServerAliveInterval=60 \
  -o ServerAliveCountMax=20 \
  -i "${METAL3_CI_USER_KEY}" \
  "${METAL3_CI_USER}"@"${TEST_EXECUTER_IP}" \
  PATH=/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:/bin \
  /tmp/run_integration_tests.sh /tmp/vars.sh "${GITHUB_TOKEN}"
