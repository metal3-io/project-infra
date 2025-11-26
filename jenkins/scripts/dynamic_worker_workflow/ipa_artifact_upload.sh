#!/bin/bash
set -eu

CURRENT_SCRIPT_DIR="$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")"
METADATA_PATH="/tmp/metadata.txt"
RT_UTILS="${RT_UTILS:-${CURRENT_SCRIPT_DIR}/../artifactory/utils.sh}"

if [ -r "${METADATA_PATH}" ]; then
    source "${METADATA_PATH}"
else
    echo "Meta data file ${METADATA_PATH} can't be found!"
    echo "Something went wrong in IPA building exiting."
    exit 1
fi
# shellcheck source=/dev/null
source "${RT_UTILS}"

REVIEW_ARTIFACTORY_PATH="metal3/images/ipa/review/${IPA_BASE_OS}/${IPA_BASE_OS_RELEASE}/${IPA_IDENTIFIER}/${IPA_IMAGE_TAR}"
STAGING_ARTIFACTORY_PATH="metal3/images/ipa/staging/${IPA_BASE_OS}/${IPA_BASE_OS_RELEASE}/${IPA_IDENTIFIER}/${IPA_IMAGE_TAR}"

if $STAGING; then
    rt_upload_artifact  "${IPA_IMAGE_TAR}" "${STAGING_ARTIFACTORY_PATH}" "0"
else
    rt_upload_artifact  "${IPA_IMAGE_TAR}" "${REVIEW_ARTIFACTORY_PATH}" "0"
fi
