#!/bin/bash
# Fail the script if any command fails
set -eu

CI_DIR="$(dirname "$(readlink -f "${0}")")"
IPA_BUILDER_SCRIPT_NAME="${IPA_BUILDER_SCRIPT_NAME:-build_ipa.sh}"

echo "Running Ironic image building script"
"${CI_DIR}/fullstack_build_ironic.sh"

IPA_REPO="${IPA_REPO:-https://opendev.org/openstack/ironic-python-agent.git}"
IPA_BRANCH="${IPA_BRANCH:-master}"
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
"${CI_DIR}/${IPA_BUILDER_SCRIPT_NAME}"
