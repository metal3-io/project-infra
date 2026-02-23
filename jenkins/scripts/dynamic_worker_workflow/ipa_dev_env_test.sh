#!/bin/bash
set -eu

METADATA_PATH="/tmp/metadata.txt"
if [ -r "${METADATA_PATH}" ]; then
    source "${METADATA_PATH}"
else
    echo "Meta data file ${METADATA_PATH} can't be found!"
    echo "Something went wrong in IPA building exiting."
    exit 1
fi

CURRENT_SCRIPT_DIR="$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")"
# Metal3 dev env repo configuration for testing the newly built IPA
export METAL3_DEV_ENV_REPO="${METAL3_DEV_ENV_REPO:-https://github.com/metal3-io/metal3-dev-env}"
export METAL3_DEV_ENV_BRANCH="${METAL3_DEV_ENV_BRANCH:-main}"
export METAL3_DEV_ENV_COMMIT="${METAL3_DEV_ENV_COMMIT:-HEAD}"
# Ironic sournce and Ironic-image repos
export IRONIC_SOURCE_REPO="${IRONIC_SOURCE_REPO:-https://opendev.org/openstack/ironic.git}"
export IRONIC_SOURCE_COMMIT="${IRONIC_SOURCE_COMMIT:-HEAD}"
export IRONIC_SOURCE_BRANCH="${IRONIC_SOURCE_BRANCH:-master}"
export IRONIC_SOURCE="${IPA_BUILD_WORKSPACE}/ironic" # Sourced by dev-env too
export IRONIC_IMAGE_REPO="${IRONIC_IMAGE_REPO:-https://github.com/metal3-io/ironic-image.git}"
export IRONIC_IMAGE_COMMIT="${IRONIC_IMAGE_REPO_COMMIT:-HEAD}"
export IRONIC_IMAGE_BRANCH="${IRONIC_IMAGE_BRANCH:-main}"
export IRONIC_IMAGE_PATH="${IPA_BUILD_WORKSPACE}/ironic-image" # Sourced by dev-env too
export IRONIC_LOCAL_IMAGE="${IRONIC_IMAGE_PATH}" # Sourced by dev-env too
# Pull dev-env
git clone --single-branch --branch "${METAL3_DEV_ENV_BRANCH}" "${METAL3_DEV_ENV_REPO}"
# Make sure the correct versions of Ironic and Ironic-image are checked out
# dev-env has no builtin cloning for ironic-image and ironic custom branches
git clone --single-branch --branch "${IRONIC_IMAGE_BRANCH}" "${IRONIC_IMAGE_REPO}" "ironic-image"
pushd "${IPA_BUILD_WORKSPACE}/ironic-image"
git checkout "${IRONIC_IMAGE_COMMIT}"
popd
git clone --single-branch --branch "${IRONIC_SOURCE_BRANCH}" "${IRONIC_SOURCE_REPO}" "ironic"
pushd "${IPA_BUILD_WORKSPACE}/ironic"
git checkout "${IRONIC_SOURCE_COMMIT}"
popd
# Components needed for a working Metal3 deployment
export BMOREPO="${BMOREPO:-https://github.com/metal3-io/baremetal-operator.git}"
export BMOBRANCH="${BMO_BRANCH:-main}"
export BMOCOMMIT="${BMO_COMMIT:-HEAD}"
export CAPM3REPO="${CAPM3_REPO:-https://github.com/metal3-io/cluster-api-provider-metal3.git}"
export CAPM3BRANCH="${CAPM3_BRANCH:-main}"
export CAPM3COMMIT="${CAPM3_COMMIT:-HEAD}"
export IPAMREPO="${IPAM_REPO:-https://github.com/metal3-io/ip-address-manager.git}"
export IPAMBRANCH="${IPAM_BRANCH:-main}"
export IPAMCOMMIT="${IPAM_COMMIT:-HEAD}"
export CAPIREPO="${CAPI_REPO:-https://github.com/kubernetes-sigs/cluster-api.git}"
export CAPIBRANCH="${CAPI_BRANCH:-main}"
export CAPICOMMIT="${CAPI_COMMIT:-HEAD}"
# Metal3 dev env local build configuration
export BUILD_CAPM3_LOCALLY="${BUILD_CAPM3_LOCALLY:-true}"
export BUILD_BMO_LOCALLY="${BUILD_BMO_LOCALLY:-true}"
export BUILD_IPAM_LOCALLY="${BUILD_IPAM_LOCALLY:-true}"
export BUILD_IRONIC_IMAGE_LOCALLY="true"
export BUILD_CAPI_LOCALLY="${BUILD_CAPI_LOCALLY:-false}"
export USE_LOCAL_IPA=true
export IPA_DOWNLOAD_ENABLED=false
# execute
pushd "${DEV_ENV_REPO_LOCATION}"
git checkout "${METAL3_DEV_ENV_COMMIT}"
METAL3_DEV_ENV_COMMIT="$(git rev-parse HEAD)"
# shellcheck source=/dev/null
source "./lib/common.sh"
# shellcheck source=/dev/null
source "./lib/releases.sh"
# Host machien supposed to have all the packages pre-installed thus running
# with make nodep
make nodep
kubectl patch bmh node-1 -n metal3 --type merge --patch-file \
    "${CURRENT_SCRIPT_DIR}/bmh-patch-short-serial.yaml"
make test
CERT_MANAGER_VERSION="$(grep -r "Installing cert-manager Version" | sed -n 's/.*\(v[0-9]\.[0-9]\.[0-9]\)"/\1/p' | head -n 1)"
popd

# Appending the metadata file with the test config info
cat << EOF > "${METADATA_PATH}"
# DEV ENV TEST CONFIG #
IRONIC_TAG="${IRONIC_TAG}"
IRONIC_REPO="${IRONIC_REPO}"
IRONIC_REFSPEC="${IRONIC_REFSPEC}"
IRONIC_COMMIT="${IRONIC_COMMIT}"
IRONIC_IMAGE_REPO="${IRONIC_IMAGE_REPO}"
IRONIC_IMAGE_REPO_COMMIT="${IRONIC_IMAGE_REPO_COMMIT}"
IRONIC_IMAGE_BRANCH="${IRONIC_IMAGE_BRANCH}"
IRONIC_INSPECTOR_REFSPEC="${IRONIC_INSPECTOR_REFSPEC}"
IRONIC_INSPECTOR_REPO="${IRONIC_INSPECTOR_REPO}"
IRONIC_INSPECTOR_COMMIT="${IRONIC_INSPECTOR_COMMIT}"
IRONIC_IMAGE_HARBOR_DIGEST="${HARBOR_ARTIFACT_DIGEST}"
METAL3_DEV_ENV_REPO="${METAL3_DEV_ENV_REPO}"
METAL3_DEV_ENV_BRANCH="${METAL3_DEV_ENV_BRANCH}"
METAL3_DEV_ENV_COMMIT="${METAL3_DEV_ENV_COMMIT}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION}"
CAPM3_REPO="${CAPM3REPO}"
CAPM3_BRANCH="${CAPM3BRANCH}"
CAPM3_COMMIT="$(git --git-dir="${CAPM3PATH}/.git" rev-parse HEAD)"
BMOREPO="${BMOREPO}"
BMO_COMMIT="$(git --git-dir="${BMOPATH}/.git" rev-parse HEAD)"
BMO_BRANCH="${BMOBRANCH}"
IPAM_REPO="${IPAMREPO}"
IPAM_BRANCH="${IPAMBRANCH}"
IPAM_COMMIT="$(git --git-dir="${IPAMPATH}/.git" rev-parse HEAD)"
EOF
if $BUILD_CAPI_LOCALLY; then
    cat << EOF >> "${METADATA_PATH}"
CAPI_REPO="${CAPIREPO}"
CAPI_BRANCH="${CAPIBRANCH}"
CAPI_COMMIT="${CAPICOMMIT}"
EOF
else
    cat << EOF >> "${METADATA_PATH}"
CAPI_RELEASE="${CAPIRELEASE}"
CAPI_VERSION="${CAPI_VERSION}"
EOF
fi

mv "${METADATA_PATH}" "metadata.txt"
tar -r -f "${IPA_IMAGE_TAR}" "metadata.txt"
