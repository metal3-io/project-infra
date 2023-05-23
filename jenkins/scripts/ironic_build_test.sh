#!/usr/bin/env bash

set -eu

# shellcheck disable=SC1090
source "${VARS_SCRIPT:-/tmp/vars.sh}"

# This script is used to build Ironic and it is used by multiple different pipelines.
# This script is designed to be executed on dynamically allocated VM-s provided
# by the CI infrastrucutre.
# Supported usecases:
#   - Build ironic-image and install ironic from source
#   - Build ironic-image and install ironic from rpm packages
#   - Build ironic-image and install ironic from rpm packages then add a patch.

IMAGE_REGISTRY="${IMAGE_REGISTRY:-localhost}"
TAG="${TAG:-test}"
CONTAINER_IMAGE_REPO="ironic-image"
DESTINATION_REPO="${DESTINATION_REPO:?}"
DESTINATION_BRANCH="${DESTINATION_BRANCH:?}"
SOURCE_REPO="${SOURCE_REPO:?}"
SOURCE_BRANCH="${SOURCE_BRANCH:?}"
PATCH_FILE=patch.txt
OS_USERNAME="${OS_USERNAME:-metal3ci}"
PATCHFILE_CONTENT="${PATCHFILE_CONTENT:-""}"
IRONIC_INSTALL_MODE="${IRONIC_INSTALL_MODE:-INSTALL_FROM_RPM}"
IRONIC_IMAGE_DIR="/home/${OS_USERNAME}/tested_repo"
CLONING_ISSUE="Non empty ${IRONIC_IMAGE_DIR} or cloning error, proceeding to check the directory."

prepare_work_env()
{
    # Clone the source repository
    git clone "${DESTINATION_REPO}" "${IRONIC_IMAGE_DIR}" || echo "${CLONING_ISSUE}"
    cd "${IRONIC_IMAGE_DIR}"
    git checkout "${DESTINATION_BRANCH}"
    # If the target and source repos and branches are identical, don't try to merge
    if [[ "${SOURCE_REPO}" != *"${DESTINATION_REPO}"* ]] ||
        [[ "${SOURCE_BRANCH}" != "${DESTINATION_BRANCH}" ]]; then
        git config user.email "test@test.test"
        git config user.name "Test"
        git remote add test "${SOURCE_REPO}"
        git fetch test
        # Merging the source branch to the destintation branch
        git merge "${SOURCE_BRANCH}" || exit
    fi
}

install_from_rpm()
{
    docker build -t "${IMAGE_REGISTRY}/${CONTAINER_IMAGE_REPO}:${TAG}" .
}

install_from_source()
{
    docker build -t "${IMAGE_REGISTRY}/${CONTAINER_IMAGE_REPO}:${TAG}" --build-arg INSTALL_TYPE=source .
}

# This script relies on upstream https://github.com/metal3-io/ironic-image/blob/main/patch-image.sh
# to build Ironic container image based on a gerrit refspec of a patch.
# Required parameter is REFSPEC, which is gerrit refspec of the patch
# Example: refs/changes/74/804074/1
install_from_rpm_patch()
{
    # Create a patchlist
    echo "ironic image will be patched with the following patchfile:"
    echo "${PATCHFILE_CONTENT}"
    cat << EOF > "${PATCH_FILE}"
${PATCHFILE_CONTENT}
EOF

    echo "ironic-image patchfile content"
    cat "${PATCH_FILE}"

    docker build -t "${IMAGE_REGISTRY}/${CONTAINER_IMAGE_REPO}:${TAG}" --build-arg PATCH_LIST="${PATCH_FILE}" .
}

# This condition will be triggered for example when the related CI tooling (project-infra PR) is being
# tested but not a PR in the ironic-image repository.

# IMPORTANT: In case it is required to test the compatibility between project-infra and ironic-image PRs
# then the test has to be triggered on the projec-infra PR then it should be manually stopped
# and replayed in a way that the destination and source branches and repositories are manually modified
# according to the inronic-image PR in question.
# Example: user have in both project-infra and in ironic-image and the user would like to test both
# together before any of them would be merged.
if [[ "${DESTINATION_REPO}" != "https://github.com/metal3-io/ironic-image.git" ]]; then
    DESTINATION_REPO="https://github.com/metal3-io/ironic-image.git"
    DESTINATION_BRANCH="main"
    SOURCE_REPO="${DESTINATION_REPO}"
    SOURCE_BRANCH="${DESTINATION_BRANCH}"
fi

case "${IRONIC_INSTALL_MODE}" in

    'INSTALL_FROM_SOURCE')
        prepare_work_env
        install_from_source
        ;;
    'INSTALL_FROM_RPM')
        prepare_work_env
        install_from_rpm
        ;;
    'INSTALL_FROM_RPM_PATCH')
        prepare_work_env
        install_from_rpm_patch
        ;;
    *)
        exit 1
        ;;
esac
