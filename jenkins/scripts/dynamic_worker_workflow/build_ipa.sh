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
IPA_BUILDER_REPO="${IPA_BUILDER_REPO:-https://opendev.org/openstack/ironic-python-agent-builder.git}"
IPA_BUILDER_BRANCH="${IPA_BUILDER_BRANCH:-master}"
IPA_BUILDER_COMMIT="${IPA_BUILDER_COMMIT:-HEAD}"
IPA_BUILD_WORKSPACE="${IPA_BUILD_WORKSPACE:-/tmp/dib}"
OPENSTACK_REQUIREMENTS_REF="${OPENSTACK_REQUIREMENTS_REF:-master}"

# General environment variables
# The following 3 vars could be usefull to be changed during testing
DISABLE_UPLOAD="${DISABLE_UPLOAD:-false}"
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
IPA_SOURCE_DOWNLOAD_CACHE="${IPA_SOURCE_DOWNLOAD_CACHE:-${HOME}/.cache/image-create/source-repositories}"

if [[ "${IPA_BASE_OS}" == "centos" ]]; then
  centos_upstream_img="CentOS-Stream-GenericCloud-9-20250812.1.x86_64.qcow2"

  if [[ ! -f "${centos_upstream_img}" ]]; then
    wget -O "${centos_upstream_img}" \
      "https://cloud.centos.org/centos/9-stream/x86_64/images/${centos_upstream_img}"
  fi

  DIB_LOCAL_IMAGE="$(pwd)/${centos_upstream_img}"
  export DIB_LOCAL_IMAGE
fi

IRONIC_SIZE_LIMIT_MB=525
DEV_ENV_REPO_LOCATION="${DEV_ENV_REPO_LOCATION:-/tmp/dib/metal3-dev-env}"
IMAGE_REGISTRY="registry.nordix.org"
CONTAINER_IMAGE_REPO="metal3"
STAGING="${STAGING:-false}"
METADATA_PATH="/tmp/metadata.txt"

sudo rm -rf "${IPA_BUILD_WORKSPACE}"
sudo rm -rf "${IPA_SOURCE_DOWNLOAD_CACHE}"
# Update apt packages
sudo apt-get update -y

# Install required packages
sudo apt-get install --yes python3-pip python3-virtualenv qemu-utils

# Clean local repository
sudo apt-get clean

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
# IDENTIFIER is the git commit of the HEAD and the ISO 8061 UTC timestamp
git clone --single-branch --branch "${IPA_BRANCH}" "${IPA_REPO}"

# Generate the IPA image identifier string
pushd "./ironic-python-agent"
# Collect IPA commit metadata for buildinfo generation
IPA_COMMIT="$(git rev-parse HEAD)"
IPA_BUILDER_COMMIT_SHORT="$(git rev-parse --short HEAD)"
IPA_IDENTIFIER="$(date --utc +"%Y%m%dT%H%MZ")-${IPA_BUILDER_COMMIT_SHORT}"
echo "IPA_IDENTIFIER is the following:${IPA_IDENTIFIER}"
popd

# Install the  previously cloned IPA builder tool
virtualenv venv
# shellcheck source=/dev/null
source "./venv/bin/activate"
python3 -m pip install --upgrade pip
python3 -m pip install "./${IPA_BUILDER_PATH}"

# Configure the IPA builder to pull the IPA source from Nordix fork
export DIB_REPOLOCATION_ironic_python_agent="${IPA_BUILD_WORKSPACE}/ironic-python-agent"
export DIB_REPOREF_requirements="${OPENSTACK_REQUIREMENTS_REF}"
export DIB_REPOREF_ironic_python_agent="${IPA_BRANCH}"
export DIB_REPOLOCATION_ironic_python_agent="${IPA_REPO}"
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
export DIB_CLEANUP_NVIDIA_GPUS="true"

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
    --element='ipa-file-injector' --element='cleanup-package' --verbose

# Clean up DIB_LOCAL_IMAGE to prevent interference in Metal3 dev-env
# when building other images based on LOCAL_IMAGE suffix
unset DIB_LOCAL_IMAGE

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
    echo "FATAL: Ironic size limit is ${IRONIC_SIZE_LIMIT_MB}MB. Size of the archive (${filesize_MB}MB) is too large."
    exit 1
fi

# Create metadata file
touch "${METADATA_PATH}"
cat << EOF > "${METADATA_PATH}"
IPA_REPO="${IPA_REPO}"
IPA_BRANCH="${IPA_BRANCH}"
IPA_COMMIT="${IPA_COMMIT}"
IPA_BUILDER_REPO="${IPA_BUILDER_REPO}"
IPA_BUILDER_BRANCH="${IPA_BUILDER_BRANCH}"
IPA_BUILDER_COMMIT="${IPA_BUILDER_COMMIT}"
IPA_BASE_OS="${IPA_BASE_OS}"
IPA_BASE_OS_RELEASE}="${IPA_BASE_OS_RELEASE}"
IPA_IDENTIFIER="${IPA_IDENTIFIER}"
IPA_IMAGE_TAR="${IPA_IMAGE_TAR}"
EOF

# Test whether the newly built IPA is compatible with the choosen Ironic version and with
# the Metal3 dev-env
if $ENABLE_BOOTSTRAP_TEST ; then
   "${CURRENT_SCRIPT_DIR}/ipa_dev_env_test.sh"
fi


# Upload the newly built image
if ! $DISABLE_UPLOAD ; then
   "${CURRENT_SCRIPT_DIR}/ipa_artifact_upload.sh"
fi
