#!/bin/bash
# Set execution parameters to:
# Fail whenever any command fails
set -eu

# The path to the directory that holds this script
CURRENT_SCRIPT_DIR="$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")"
# Repository configuration options
# IPA BRANCH IS PINNED ATM
IPA_REPO="${IPA_REPO:-https://opendev.org/openstack/ironic-python-agent.git}"
IPA_BRANCH="${IPA_BRANCH:-master}"
IPA_REF="${IPA_REF:-HEAD}"
IPA_BUILDER_REPO="${IPA_BUILDER_REPO:-https://opendev.org/openstack/ironic-python-agent-builder.git}"
IPA_BUILDER_BRANCH="${IPA_BUILDER_BRANCH:-master}"
IPA_BUILDER_COMMIT="${IPA_BUILDER_COMMIT:-HEAD}"
IPA_BUILD_WORKSPACE="${IPA_BUILD_WORKSPACE:-/tmp/dib}"
OPENSTACK_REQUIREMENTS_REF="${OPENSTACK_REQUIREMENTS_REF:-master}"
# Metal3 dev env repo configuration for testing the newly built IPA
METAL3_DEV_ENV_REPO="${METAL3_DEV_ENV_REPO:-https://github.com/metal3-io/metal3-dev-env}"
METAL3_DEV_ENV_BRANCH="${METAL3_DEV_ENV_BRANCH:-main}"
METAL3_DEV_ENV_COMMIT="${METAL3_DEV_ENV_COMMIT:-HEAD}"
# Components needed for a working Metal3 deployment
# Changes done to the component's git configuration makes a difference only
# in case local image building is enabled.
BMOREPO="${BMOREPO:-https://github.com/metal3-io/baremetal-operator.git}"
BMOBRANCH="${BMO_BRANCH:-main}"
BMOCOMMIT="${BMO_COMMIT:-HEAD}"
CAPM3REPO="${CAPM3_REPO:-https://github.com/metal3-io/cluster-api-provider-metal3.git}"
CAPM3BRANCH="${CAPM3_BRANCH:-main}"
CAPM3COMMIT="${CAPM3_COMMIT:-HEAD}"
IPAMREPO="${IPAM_REPO:-https://github.com/metal3-io/ip-address-manager.git}"
IPAMBRANCH="${IPAM_BRANCH:-main}"
IPAMCOMMIT="${IPAM_COMMIT:-HEAD}"
CAPIREPO="${CAPI_REPO:-https://github.com/kubernetes-sigs/cluster-api.git}"
CAPIBRANCH="${CAPI_BRANCH:-main}"
CAPICOMMIT="${CAPI_COMMIT:-HEAD}"
# Metal3 dev env local build configuration
BUILD_CAPM3_LOCALLY="${BUILD_CAPM3_LOCALLY:-true}"
BUILD_BMO_LOCALLY="${BUILD_BMO_LOCALLY:-true}"
BUILD_IPAM_LOCALLY="${BUILD_IPAM_LOCALLY:-true}"
BUILD_CAPI_LOCALLY="${BUILD_CAPI_LOCALLY:-false}"

# General environment variables
# The following 3 vars could be usefull to be changed during testing
DISABLE_UPLOAD="${DISABLE_UPLOAD:-false}"
RT_UTILS="${RT_UTILS:-/tmp/utils.sh}"
ENABLE_BOOTSTRAP_TEST="${ENABLE_BOOTSTRAP_TEST:-true}"
TEST_IN_CI="${TEST_IN_CI:-true}"
ENABLE_DEV_USER_PASS="${ENABLE_DEV_USER_PASS:-false}"
ENABLE_DEV_USER_SSH="${ENABLE_DEV_USER_SSH:-false}"
DEV_USER_SSH_PATH="${DEV_USER_SSH_PATH:-$HOME/.ssh/id_rsa.pub}"


RT_URL="${RT_URL:-https://artifactory.nordix.org/artifactory}"
IPA_BUILDER_PATH="ironic-python-agent-builder"
IPA_IMAGE_NAME="${IPA_IMAGE_NAME:-ironic-python-agent}"
IPA_IMAGE_TAR="${IPA_IMAGE_NAME}.tar"
IPA_BASE_OS="${IPA_BASE_OS:-centos}"
IPA_BASE_OS_RELEASE="${IPA_BASE_OS_RELEASE:-9-stream}"
IRONIC_SIZE_LIMIT_MB=500
DEV_ENV_REPO_LOCATION="${DEV_ENV_REPO_LOCATION:-/tmp/dib/metal3-dev-env}"
IMAGE_REGISTRY="registry.nordix.org"
CONTAINER_IMAGE_REPO="metal3"
STAGING="${STAGING:-false}"
METADATA_PATH="/tmp/metadata.txt"

sudo rm -rf "${IPA_BUILD_WORKSPACE}"

# Install required packages
sudo apt-get install --yes python3-pip python3-virtualenv qemu-utils

# Create the work directory
mkdir --parents "${IPA_BUILD_WORKSPACE}"
cd "${IPA_BUILD_WORKSPACE}"

# Pull IPA builder repository
git clone --single-branch --branch "${IPA_BUILDER_BRANCH}" "${IPA_BUILDER_REPO}"
pushd "./ironic-python-agent-builder"
git checkout "${IPA_BUILDER_COMMIT}"
IPA_BUILDER_COMMIT="$(git rev-parse  HEAD)"

# Handle oslo-log dependency issue, the issue is caused by a missmatch between
# IPA dependency list and this https://opendev.org/openstack/requirements/src/branch/master/upper-constraints.txt
# shellcheck disable=SC2016
sed -i '43i sed -i "s/oslo.log===5.0.0//" "$UPPER_CONSTRAINTS"' \
    "${IPA_BUILD_WORKSPACE}/${IPA_BUILDER_PATH}/dib/ironic-python-agent-ramdisk/install.d/ironic-python-agent-ramdisk-source-install/60-ironic-python-agent-ramdisk-install"
popd

# Pull IPA repository to create IPA_IDENTIFIER
git clone --single-branch --branch "${IPA_BRANCH}" "${IPA_REPO}"

# Generate the IPA image identifier string
pushd "./ironic-python-agent"
# IDENTIFIER is the git commit of the HEAD and the ISO 8061 UTC timestamp
git checkout "${IPA_REF}"
IPA_COMMIT="$(git rev-parse HEAD)"
IPA_BUILDER_COMMIT_SHORT="$(git rev-parse --short HEAD)"
IPA_IDENTIFIER="$(date --utc +"%Y%m%dT%H%MZ")-${IPA_BUILDER_COMMIT_SHORT}"
echo "IPA_IDENTIFIER is the following:${IPA_IDENTIFIER}"
popd

# Install the cloned IPA builder tool
virtualenv venv
# shellcheck source=/dev/null
source "./venv/bin/activate"
python3 -m pip install --upgrade pip
python3 -m pip install "./${IPA_BUILDER_PATH}"

# Configure the IPA builder to pull the IPA source from Nordix fork
export DIB_REPOLOCATION_ironic_python_agent="${IPA_BUILD_WORKSPACE}/ironic-python-agent"
export DIB_REPOREF_requirements="${OPENSTACK_REQUIREMENTS_REF}"
export DIB_REPOREF_ironic_python_agent="${IPA_REF}"
export DIB_DEV_USER_USERNAME=metal3
if [ "${ENABLE_DEV_USER_PASS}" == "true" ]; then
export DIB_DEV_USER_PWDLESS_SUDO=yes
export DIB_DEV_USER_PASSWORD="metal3"
fi
if [ "${ENABLE_DEV_USER_SSH}" == "true" ]; then
export DIB_DEV_USER_AUTHORIZED_KEYS="${DEV_USER_SSH_PATH}"
fi
export DIB_INSTALLTYPE_simple_init="repo"
export DIB_REPOLOCATION_glean="https://github.com/Nordix/glean.git"
export DIB_REPOREF_glean="refs/heads/parsing_error"

# IPA builder customisation variables
# Path to custom IPA builder kernel module element
CUSTOM_ELEMENTS="${CURRENT_SCRIPT_DIR}/ipa_builder_elements"
# List of additional kernel modules that should be loaded during boot separated by ':'
# This list is used by the custom element named ipa-modprobe
export ADDITIONAL_IPA_KERNEL_MODULES="megaraid_sas hpsa"

# Build the IPA initramfs and kernel images
ironic-python-agent-builder --output "${IPA_IMAGE_NAME}" \
    --release "${IPA_BASE_OS_RELEASE}" "${IPA_BASE_OS}" \
    --elements-path="${CUSTOM_ELEMENTS}" \
    --element='dynamic-login' --element='journal-to-console' \
    --element='devuser' --element='openssh-server' \
    --element='extra-hardware' --element='ipa-module-autoload' \
    --element='ipa-add-buildinfo' --element='ipa-cleanup-dracut' \
    --element='simple-init' --element='override-simple-init' \
    --element='ipa-file-injector' --verbose

# Deactivate the python virtual environment
deactivate

# Package the initramfs and kernel images to a tar archive
tar --create --verbose --file="${IPA_IMAGE_TAR}" \
    "${IPA_IMAGE_NAME}.kernel" \
    "${IPA_IMAGE_NAME}.initramfs"

# Check the size of the archive
filesize=$(stat --printf="%s" /tmp/dib/ironic-python-agent.tar)
size_domain_offset=1024
filesize_MB=$((filesize / size_domain_offset / size_domain_offset))
echo "Size of the archive: ${filesize_MB}MB"
if [ ${filesize_MB} -ge ${IRONIC_SIZE_LIMIT_MB} ]; then
    exit 1
fi

# Test whether the newly built IPA is compatible with the choosen Ironic version and with
# the Metal3 dev-env
if $ENABLE_BOOTSTRAP_TEST; then
    git clone --single-branch --branch "${METAL3_DEV_ENV_BRANCH}" "${METAL3_DEV_ENV_REPO}"
    if $TEST_IN_CI; then
        # shellcheck source=/dev/null
        source "/tmp/vars.sh"
        export IRONIC_IMAGE="${IMAGE_REGISTRY}/${CONTAINER_IMAGE_REPO}/ironic-image:${IRONIC_TAG}"
    fi
    export USE_LOCAL_IPA=true
    export IPA_DOWNLOAD_ENABLED=false
    export BMOREPO
    export BMOBRANCH
    export BMOCOMMIT
    export CAPM3REPO
    export CAPM3BRANCH
    export CAPM3COMMIT
    export IPAMREPO
    export IPAMBRANCH
    export IPAMCOMMIT
    export CAPIREPO
    export CAPIBRANCH
    export CAPICOMMIT
    export BUILD_CAPM3_LOCALLY
    export BUILD_BMO_LOCALLY
    export BUILD_IPAM_LOCALLY
    export BUILD_CAPI_LOCALLY
    # execute
    pushd "${DEV_ENV_REPO_LOCATION}"
    git checkout "${METAL3_DEV_ENV_COMMIT}"
    METAL3_DEV_ENV_COMMIT="$(git rev-parse HEAD)"
    # shellcheck source=/dev/null
    source "./lib/common.sh"
    # shellcheck source=/dev/null
    source "./lib/releases.sh"
    make
    kubectl patch bmh node-1 -n metal3 --type merge --patch-file \
        "/tmp/bmh-patch-short-serial.yaml"
    make test
    CERT_MANAGER_VERSION="$(grep -r "Installing cert-manager Version" |sed -n 's/.*\(v[0-9]\.[0-9]\.[0-9]\)"/\1/p' | head -n 1)"
    cat << EOF >> "${METADATA_PATH}"
METAL3_DEV_ENV_REPO="${METAL3_DEV_ENV_REPO}"
METAL3_DEV_ENV_BRANCH="${METAL3_DEV_ENV_BRANCH}"
METAL3_DEV_ENV_COMMIT="${METAL3_DEV_ENV_COMMIT}"
IPA_REPO="${IPA_REPO}"
IPA_BRANCH="${IPA_BRANCH}"
IPA_COMMIT="${IPA_COMMIT}"
IPA_BUILDER_REPO="${IPA_BUILDER_REPO}"
IPA_BUILDER_BRANCH="${IPA_BUILDER_BRANCH}"
IPA_BUILDER_COMMIT="${IPA_BUILDER_COMMIT}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION}"
EOF
    pushd "${BMOPATH}"
    cat << EOF >> "${METADATA_PATH}"
BMOREPO="${BMOREPO}"
BMO_BRANCH="${BMOBRANCH}"
BMO_COMMIT="$(git rev-parse HEAD)"
EOF
    popd
    pushd "${CAPM3PATH}"
    cat << EOF >> "${METADATA_PATH}"
CAPM3_REPO="${CAPM3REPO}"
CAPM3_BRANCH="${CAPM3BRANCH}"
CAPM3_COMMIT="$(git rev-parse HEAD)"
EOF
    popd
    pushd "${IPAMPATH}"
    cat << EOF >> "${METADATA_PATH}"
IPAM_REPO="${IPAMREPO}"
IPAM_BRANCH="${IPAMBRANCH}"
IPAM_COMMIT="$(git rev-parse HEAD)"
EOF
    popd
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
    popd
fi

mv "${METADATA_PATH}" "metadata.txt"
tar -r -f "${IPA_IMAGE_TAR}" "metadata.txt"

REVIEW_ARTIFACTORY_PATH="metal3/images/ipa/review/${IPA_BASE_OS}/${IPA_BASE_OS_RELEASE}/${IPA_IDENTIFIER}/${IPA_IMAGE_TAR}"
STAGING_ARTIFACTORY_PATH="metal3/images/ipa/staging/${IPA_BASE_OS}/${IPA_BASE_OS_RELEASE}/${IPA_IDENTIFIER}/${IPA_IMAGE_TAR}"
# Upload the newly built image
if ! $DISABLE_UPLOAD ; then
    # shellcheck source=/dev/null
    source "${RT_UTILS}"
    if $STAGING; then
        rt_upload_artifact  "${IPA_IMAGE_TAR}" "${STAGING_ARTIFACTORY_PATH}" "0"
    else
        rt_upload_artifact  "${IPA_IMAGE_TAR}" "${REVIEW_ARTIFACTORY_PATH}" "0"
    fi
fi

